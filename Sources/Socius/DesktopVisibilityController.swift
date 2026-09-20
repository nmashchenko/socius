import AppKit
import CyclopTools

/// Detect immersive presentation using public presentation flags and window bounds.
/// Window titles and pixels are never read; no Accessibility/Screen Recording grant is needed.
final class DesktopVisibilityController {
    private let window: PetPanel
    private let model: PetModel
    private let presence: EdgeDockController
    private let hub: ToolHub
    private var observation: NSKeyValueObservation?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var observing = false
    private var windowCheck: Timer?
    var changed: (Bool) -> Void = { _ in }

    init(window: PetPanel, model: PetModel, presence: EdgeDockController, hub: ToolHub) {
        self.window = window
        self.model = model
        self.presence = presence
        self.hub = hub
    }

    static func shouldHide(for options: NSApplication.PresentationOptions) -> Bool {
        if options.contains(.fullScreen) { return true }
        // Older video players and games use presentation mode in the current Space.
        let hiddenMenu = !options.intersection([.hideMenuBar, .autoHideMenuBar]).isEmpty
        let hiddenDock = !options.intersection([.hideDock, .autoHideDock]).isEmpty
        return hiddenMenu && hiddenDock
    }

    static func fillsDisplay(_ window: CGRect, display: CGRect) -> Bool {
        guard !window.isEmpty, !display.isEmpty else { return false }
        return abs(window.minX - display.minX) <= 2 && abs(window.minY - display.minY) <= 2
            && abs(window.maxX - display.maxX) <= 2 && abs(window.maxY - display.maxY) <= 2
    }

    private func anotherAppFillsDisplay() -> Bool {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return false }
        let displays = NSScreen.screens.compactMap { screen -> CGRect? in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            return CGDisplayBounds(number.uint32Value)
        }
        return windows.contains { window in
            guard let owner = window[kCGWindowOwnerPID as String] as? Int32,
                  owner != ProcessInfo.processInfo.processIdentifier,
                  let layer = window[kCGWindowLayer as String] as? Int, layer >= 0,
                  (window[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let dictionary = window[kCGWindowBounds as String] as? [String: Any],
                  let frame = CGRect(dictionaryRepresentation: dictionary as CFDictionary) else { return false }
            guard displays.contains(where: { Self.fillsDisplay(frame, display: $0) }) else { return false }
            // Keep a fullscreen video on a second display unobstructed even
            // while another app has focus. Exclude system/background surfaces.
            return NSRunningApplication(processIdentifier: owner)?.activationPolicy == .regular
        }
    }

    func start() {
        stop()
        observing = true
        observation = NSApp.observe(\.currentSystemPresentationOptions) { [weak self] _, _ in
            Task { @MainActor in self?.refresh() }
        }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            })
        }
        // Background accessory apps can keep reporting presentation options = 0
        // during another app's fullscreen session. Borderless video can also
        // resize without changing Space or activation, so check bounds once a second.
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        windowCheck = timer
        refresh()
    }

    func stop() {
        observing = false
        windowCheck?.invalidate()
        windowCheck = nil
        observation?.invalidate()
        observation = nil
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        workspaceObservers.removeAll()
    }

    private func refresh() {
        guard observing else { return }
        setSuppressed(Self.shouldHide(for: NSApp.currentSystemPresentationOptions) || anotherAppFillsDisplay())
    }

    func setSuppressed(_ suppressed: Bool) {
        guard model.desktopSuppressed != suppressed else { return }
        model.desktopSuppressed = suppressed
        InteractionTrace.record("desktop fullscreen suppressed=\(suppressed)")
        if suppressed {
            hub.openRequest = 0
            hub.dismissRequest += 1
            for child in window.childWindows ?? [] { child.orderOut(nil) }
            window.orderOut(nil)
            presence.suspendPresentation()
            hub.cyclop.closePresentation()
        } else {
            presence.resumePresentation()
            if !model.onboardingActive, !NSApp.isHidden { window.orderFrontRegardless() }
        }
        changed(suppressed)
        InteractionTrace.record("desktop visibility suppressed=\(suppressed) petVisible=\(window.isVisible) visibleChildren=\(window.childWindows?.filter(\.isVisible).count ?? 0) frame=\(window.frame)")
    }
}
