import AppKit
import SwiftUI

@main struct SociusApp: App {
    init() {
        if CommandLine.arguments.contains("--claude-statusline") {
            ClaudeUsageBridge.receive()
            exit(0)
        }
    }
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene { Settings { EmptyView() } }
}

final class PetPanel: NSPanel {
    weak var petInput: PetPointerRegion?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func sendEvent(_ event: NSEvent) {
        if petInput?.handle(event) == true { return }
        super.sendEvent(event)
    }
}

final class PetHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private var petPanel: PetPanel?
    private var studio: NSWindow?
    private var welcome: NSWindow?
    private let hotkey = PetHotkey()
    private lazy var tools = ToolHub()
    private var statusItem: NSStatusItem?
    private var careClock: Task<Void, Never>?
    let pet = PetModel(preferences: CommandLine.arguments.contains("--render-preview") ? nil : .standard)
    private lazy var edgeDock = EdgeDockController(model: pet)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if CommandLine.arguments.contains("--render-preview") {
            if CommandLine.arguments.contains("--sleeping") { pet.sleep() }
            if CommandLine.arguments.contains("--pocket") { pet.panelOpen = true }
            let toolName = CommandLine.arguments.firstIndex(of: "--tool").flatMap { index in
                CommandLine.arguments.indices.contains(index + 1) ? CommandLine.arguments[index + 1] : nil
            }
            let previewDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("SociusPreview-\(UUID())")
            defer { try? FileManager.default.removeItem(at: previewDirectory) }
            let previewHub = ToolHub(store: ToolStore(directory: previewDirectory))
            previewHub.selected = toolName.flatMap(PocketTool.init(rawValue:)) ?? .notes
            if toolName != nil {
                _ = previewHub.store.saveText(TextItem(title: "A thought for later", text: "A little place for the ideas that arrive while you’re doing something else."), in: .notes)
                _ = previewHub.store.saveText(TextItem(title: "Friday plans", text: "Finish the tiny things. Take a walk. Find Mochi a shrimp."), in: .notes)
                _ = previewHub.store.saveText(TextItem(title: "A friendly follow-up", text: "Thanks for your time today! Here are the next steps we discussed."), in: .snippets)
            }
            if toolName == "Shelf" {
                let sample = previewDirectory.appendingPathComponent("Screenshot.png")
                let existingPreview = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("build/tool-preview.png")
                if (try? FileManager.default.copyItem(at: existingPreview, to: sample)) != nil {
                    _ = previewHub.store.update { $0.shelf = [ShelfItem(path: sample.path)] }
                }
            }
            let width: CGFloat = toolName == nil ? 1000 : toolName == "Home" ? 380 : 420
            let height: CGFloat = toolName == nil ? 740 : toolName == "Home" ? 350 : previewHub.toolHeight
            let view = Group {
                if CommandLine.arguments.contains("--welcome") { WelcomeView(model: pet, finish: {}) }
                else if toolName == "Home" { PocketView(model: pet, close: {}, nativePopover: true, hub: previewHub) }
                else if toolName != nil { PocketToolView(hub: previewHub, pet: pet, back: {}, close: {}) }
                else { PlaygroundView() }
            }.frame(width: width, height: height)
            let host = NSHostingView(rootView: view)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height), styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = host
            window.orderFrontRegardless()
            host.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            if let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                host.cacheDisplay(in: host.bounds, to: bitmap)
                if let png = bitmap.representation(using: .png, properties: [:]) {
                    try? png.write(to: URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(toolName != nil ? "build/tool-preview.png" : CommandLine.arguments.contains("--sleeping") ? "build/sleep-preview.png" : CommandLine.arguments.contains("--pocket") ? "build/pocket-preview.png" : "build/interaction-preview.png"))
                }
            }
            window.orderOut(nil)
            NSApp.terminate(nil)
            return
        }
        let panel = PetPanel(contentRect: NSRect(x: 0, y: 0, width: 240, height: 270), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.level = .floating; panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = false; panel.hidesOnDeactivate = false
        let studioAction: (() -> Void)? = CommandLine.arguments.contains("--developer") ? { [weak self] in self?.showStudio() } : nil
        panel.contentView = PetHostingView(rootView: DesktopPetView(model: pet, presence: edgeDock, openStudio: studioAction, hub: tools))
        if let screen = NSScreen.main { panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.maxX - 285, y: screen.visibleFrame.minY + 40)) }
        petPanel = panel
        edgeDock.start(window: panel)
        hotkey.action = { [weak self] in self?.bringToCursor() }
        pet.shortcutChanged = { [weak self] in self?.registerShortcut() }
        registerShortcut()
        tools.cyclop.start()
        careClock = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
                self?.pet.tick()
            }
        }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "Socius")
        let menu = NSMenu()
        if CommandLine.arguments.contains("--developer") {
            menu.addItem(withTitle: "Interaction playground", action: #selector(showStudio), keyEquivalent: "")
        }
        menu.addItem(withTitle: "Bring pet back", action: #selector(bringBack), keyEquivalent: "")
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Socius", action: #selector(quit), keyEquivalent: "q")
        for entry in menu.items { entry.target = self }
        item.menu = menu; statusItem = item
        if let flag = CommandLine.arguments.firstIndex(of: "--tool"), CommandLine.arguments.indices.contains(flag + 1),
           let tool = PocketTool(rawValue: CommandLine.arguments[flag + 1]) { panel.orderFrontRegardless(); showTool(tool) }
        else if CommandLine.arguments.contains("--onboarding") || !UserDefaults.standard.bool(forKey: "didWelcomePet") {
            showWelcome()
        } else {
            edgeDock.beginIdle()
            panel.orderFrontRegardless()
            if CommandLine.arguments.contains("--developer") { showStudio() }
        }
    }
    func applicationDidChangeScreenParameters(_ notification: Notification) { edgeDock.screenChanged() }
    func showTool(_ tool: PocketTool) {
        guard pet.toolsAvailable || tool == .settings else { return }
        tools.selected = tool
        tools.store.notice = nil
        tools.showingTool = true
        tools.openRequest += 1
    }
    private func registerShortcut() {
        pet.shortcutError = hotkey.register(pet.shortcut) ? nil : "That shortcut is unavailable. Choose another combination."
    }
    private func bringToCursor() {
        guard welcome == nil, let panel = petPanel else { return }
        let point = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) else { return }
        edgeDock.repositionHome(EdgeDockGeometry.restoredFrame(home: CGRect(x: point.x - 120, y: point.y - 130,
            width: panel.frame.width, height: panel.frame.height), visibleScreen: screen.visibleFrame))
        panel.orderFrontRegardless()
    }
    @objc func showSettings() { showTool(.settings) }
    private func showWelcome() {
        guard welcome == nil else { return }
        pet.cancelActivity()
        if let panel = petPanel { edgeDock.repositionHome(panel.frame) }
        // Screen 1 is the primary display, not the display of the focused window.
        guard let screen = NSScreen.screens.first else { edgeDock.beginIdle(); return }
        edgeDock.menuOpen = true
        petPanel?.orderOut(nil)
        let window = PetPanel(contentRect: screen.visibleFrame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false; window.backgroundColor = .clear
        window.level = .floating; window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: WelcomeView(model: pet) { [weak self] in self?.finishWelcome() })
        welcome = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    private func finishWelcome() {
        guard let welcome else { return }
        UserDefaults.standard.set(true, forKey: "didWelcomePet")
        // Match the onboarding sprite exactly. DesktopPetView's 70/140/40
        // stack puts the pet center 120 points above its 270-point panel bottom.
        if let panel = petPanel {
            edgeDock.repositionHome(CGRect(x: welcome.frame.midX - panel.frame.width / 2,
                y: welcome.frame.midY - 120, width: panel.frame.width, height: panel.frame.height))
            panel.orderFrontRegardless()
            panel.displayIfNeeded()
        }
        welcome.orderOut(nil)
        welcome.contentView = nil
        self.welcome = nil
        edgeDock.menuOpen = false
        edgeDock.simulateIdle()
    }
    @objc func showStudio() {
        guard CommandLine.arguments.contains("--developer") else { return }
        if studio == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 740), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "Socius · Interaction playground"
            window.titlebarAppearsTransparent = true
            window.backgroundColor = NSColor(red: 0.96, green: 0.95, blue: 0.91, alpha: 1)
            window.minSize = NSSize(width: 900, height: 680)
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: PlaygroundView(replayOnboarding: { [weak self] in self?.showWelcome() }))
            window.center(); studio = window
        }
        studio?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    @objc func bringBack() {
        if let screen = NSScreen.main, let panel = petPanel {
            edgeDock.repositionHome(CGRect(x: screen.visibleFrame.maxX - 285, y: screen.visibleFrame.minY + 40, width: panel.frame.width, height: panel.frame.height))
        }
        petPanel?.orderFrontRegardless()
    }
    func applicationWillTerminate(_ notification: Notification) {
        careClock?.cancel()
        hotkey.stop()
        edgeDock.stop()
        tools.cyclop.stop()
        tools.store.stop()
    }
    @objc func quit() { NSApp.terminate(nil) }
}
