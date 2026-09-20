import AppKit
@preconcurrency import ApplicationServices
import Observation

nonisolated struct SavedWindow: Codable, Identifiable {
    var id = UUID()
    var bundleID: String
    var appName: String
    var title: String
    var index: Int
    var screenID: UInt32
    /// Fractions of the display's usable frame, in accessibility (top-left) coordinates.
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}

nonisolated struct WindowLayout: Codable, Identifiable {
    var id = UUID()
    var name: String
    var windows: [SavedWindow]
}

nonisolated enum LayoutGeometry {
    static func restored(_ window: SavedWindow, on screen: CGRect) -> CGRect {
        let width = min(screen.width, max(100, window.width * screen.width))
        let height = min(screen.height, max(100, window.height * screen.height))
        return CGRect(x: min(screen.maxX - width, max(screen.minX, screen.minX + window.x * screen.width)),
                      y: min(screen.maxY - height, max(screen.minY, screen.minY + window.y * screen.height)),
                      width: width, height: height)
    }
}


nonisolated struct LayoutDisplay: Sendable {
    var id: UInt32
    var frame: CGRect
}
nonisolated struct LayoutApp: Sendable {
    var pid: pid_t
    var bundleID: String
    var name: String
}
nonisolated struct LayoutResult: Sendable {
    var moved = 0
    var skipped = 0
}

/// AX calls are synchronous IPC. Keep both enumeration and mutation off the UI actor.
nonisolated enum WindowAccess {
    static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success else { return nil }
        return result
    }
    static func windows(pid: pid_t) -> [AXUIElement] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.15)
        return (value(app, kAXWindowsAttribute) as? [AXUIElement] ?? []).filter {
            AXUIElementSetMessagingTimeout($0, 0.15)
            return (value($0, kAXSubroleAttribute) as? String) == kAXStandardWindowSubrole &&
                (value($0, kAXMinimizedAttribute) as? Bool) != true &&
                (value($0, "AXFullScreen") as? Bool) != true
        }
    }
    static func frame(_ window: AXUIElement) -> CGRect? {
        guard let p = value(window, kAXPositionAttribute), CFGetTypeID(p) == AXValueGetTypeID(),
              let s = value(window, kAXSizeAttribute), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero; var size = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &point), AXValueGetValue(s as! AXValue, .cgSize, &size),
              size.width > 0, size.height > 0 else { return nil }
        return CGRect(origin: point, size: size)
    }
    @concurrent static func capture(app: LayoutApp, displays: [LayoutDisplay]) async -> [SavedWindow] {
        var result: [SavedWindow] = []
        for (index, window) in windows(pid: app.pid).enumerated() {
            guard !Task.isCancelled else { break }
            guard let rect = frame(window), let screen = displays.max(by: {
                area($0.frame.intersection(rect)) < area($1.frame.intersection(rect))
            }) else { continue }
            var movable: DarwinBoolean = false
            guard AXUIElementIsAttributeSettable(window, kAXPositionAttribute as CFString, &movable) == .success, movable.boolValue else { continue }
            result.append(SavedWindow(bundleID: app.bundleID, appName: app.name,
                title: value(window, kAXTitleAttribute) as? String ?? "", index: index, screenID: screen.id,
                x: (rect.minX - screen.frame.minX) / screen.frame.width, y: (rect.minY - screen.frame.minY) / screen.frame.height,
                width: rect.width / screen.frame.width, height: rect.height / screen.frame.height))
        }
        return result
    }
    private static func area(_ rect: CGRect) -> CGFloat { rect.isNull ? 0 : rect.width * rect.height }
    @concurrent static func restore(pid: pid_t, targets: [SavedWindow], displays: [LayoutDisplay], newlyLaunched: Bool) async -> LayoutResult {
        var available = windows(pid: pid)
        if newlyLaunched {
            for _ in 0..<5 where available.isEmpty && !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                available = windows(pid: pid)
            }
        }
        // Cache titles once instead of asking every window repeatedly for every saved target.
        let titles = available.map { value($0, kAXTitleAttribute) as? String ?? "" }
        var used = Set<Int>()
        var result = LayoutResult()
        for saved in targets {
            guard !Task.isCancelled else { break }
            let index = available.indices.first { !used.contains($0) && !saved.title.isEmpty && titles[$0] == saved.title }
                ?? (available.indices.contains(saved.index) && !used.contains(saved.index) ? saved.index : available.indices.first { !used.contains($0) })
            guard let index, let display = displays.first(where: { $0.id == saved.screenID }) ?? displays.first else { result.skipped += 1; continue }
            used.insert(index)
            let target = LayoutGeometry.restored(saved, on: display.frame)
            let window = available[index]
            if let current = frame(window), abs(current.minX - target.minX) < 2, abs(current.minY - target.minY) < 2,
               abs(current.width - target.width) < 2, abs(current.height - target.height) < 2 {
                result.moved += 1
                continue
            }
            var origin = target.origin; var size = target.size
            guard let position = AXValueCreate(.cgPoint, &origin), let dimensions = AXValueCreate(.cgSize, &size) else { result.skipped += 1; continue }
            _ = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position)
            let resized = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, dimensions)
            let positioned = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position)
            if resized == .success && positioned == .success { result.moved += 1 } else { result.skipped += 1 }
        }
        return result
    }
}

@Observable final class WindowLayoutService {
    private(set) var busy = false
    private(set) var trusted: Bool
    var message: String?
    private(set) var requestedAccess = false
    @ObservationIgnored private let checkAccess: () -> Bool
    @ObservationIgnored private let promptForAccess: () -> Void
    @ObservationIgnored private let openAccessSettings: () -> Void
    @ObservationIgnored private var permissionWatch: Task<Void, Never>?

    init(checkAccess: @escaping () -> Bool = { AXIsProcessTrusted() },
         promptForAccess: @escaping () -> Void = {
             let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
             _ = AXIsProcessTrustedWithOptions(options)
         },
         openAccessSettings: @escaping () -> Void = {
             NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
         }) {
        self.checkAccess = checkAccess
        self.promptForAccess = promptForAccess
        self.openAccessSettings = openAccessSettings
        trusted = checkAccess()
    }
    func refreshAccess() {
        let allowed = checkAccess()
        if allowed && !trusted { message = nil }
        trusted = allowed
        if allowed { permissionWatch?.cancel(); permissionWatch = nil }
    }
    func requestAccess() {
        refreshAccess()
        guard !trusted else { return }
        if requestedAccess {
            openAccessSettings()
        } else {
            requestedAccess = true
            // The system prompt already has an Open System Settings button.
            promptForAccess()
        }
        message = "Enable Socius in Privacy & Security → Accessibility. This updates automatically when access is granted."
        refreshAccess()
        guard !trusted else { message = nil; return }
        permissionWatch?.cancel()
        // Survive the pocket closing when System Settings takes focus.
        permissionWatch = Task { [weak self] in
            let deadline = ContinuousClock.now.advanced(by: .seconds(300))
            while !Task.isCancelled && ContinuousClock.now < deadline {
                do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
                guard self != nil else { return }
                self?.refreshAccess()
                if self?.trusted == true { return }
            }
        }
    }
    private var screens: [LayoutDisplay] {
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        return NSScreen.screens.map {
            let f = $0.visibleFrame
            return LayoutDisplay(id: ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0,
                frame: CGRect(x: f.minX, y: top - f.maxY, width: f.width, height: f.height))
        }
    }
    func capture(name: String) async -> WindowLayout? {
        refreshAccess()
        guard trusted else { requestAccess(); return nil }
        guard !busy else { return nil }
        busy = true; defer { busy = false }
        let displays = screens
        let apps = NSWorkspace.shared.runningApplications.compactMap { app -> LayoutApp? in
            guard app.activationPolicy == .regular, app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
                  let bundle = app.bundleIdentifier else { return nil }
            return LayoutApp(pid: app.processIdentifier, bundleID: bundle, name: app.localizedName ?? bundle)
        }
        var saved: [SavedWindow] = []
        message = "Reading your window positions…"
        for start in stride(from: 0, to: apps.count, by: 3) {
            await withTaskGroup(of: [SavedWindow].self) { group in
                for app in apps[start..<min(start + 3, apps.count)] {
                    group.addTask { await WindowAccess.capture(app: app, displays: displays) }
                }
                for await windows in group { saved.append(contentsOf: windows) }
            }
        }
        guard !saved.isEmpty else { message = "No movable windows found. Open the apps you want in this layout."; return nil }
        saved.sort { ($0.bundleID, $0.index) < ($1.bundleID, $1.index) }
        message = "Saved positions for \(saved.count) windows."
        return WindowLayout(name: name.trimmingCharacters(in: .whitespacesAndNewlines), windows: saved)
    }
    func restore(_ layout: WindowLayout) async {
        refreshAccess()
        guard trusted else { requestAccess(); return }
        guard !busy else { return }
        busy = true; defer { busy = false }
        let bundles = Set(layout.windows.map(\.bundleID)).sorted()
        let displays = screens
        var result = LayoutResult()
        var completed = 0
        message = "Restoring \(bundles.count) apps…"
        for start in stride(from: 0, to: bundles.count, by: 3) {
            await withTaskGroup(of: LayoutResult.self) { group in
                for bundle in bundles[start..<min(start + 3, bundles.count)] {
                    let targets = layout.windows.filter { $0.bundleID == bundle }
                    group.addTask { await self.restoreApp(bundle: bundle, targets: targets, displays: displays) }
                }
                for await partial in group {
                    result.moved += partial.moved; result.skipped += partial.skipped; completed += 1
                    message = "Restoring apps · \(completed) of \(bundles.count)"
                }
            }
        }
        message = "Restored \(result.moved) windows." + (result.skipped > 0 ? " \(result.skipped) unavailable or could not be resized." : "")
    }
    private func restoreApp(bundle: String, targets: [SavedWindow], displays: [LayoutDisplay]) async -> LayoutResult {
        var app = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first
        let newlyLaunched = app == nil
        if app == nil, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) {
            let config = NSWorkspace.OpenConfiguration(); config.activates = false
            app = try? await NSWorkspace.shared.openApplication(at: url, configuration: config)
        }
        guard let app else { return LayoutResult(skipped: targets.count) }
        return await WindowAccess.restore(pid: app.processIdentifier, targets: targets, displays: displays, newlyLaunched: newlyLaunched)
    }
}
