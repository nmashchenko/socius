import CyclopTools
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
    func suspendDesktopPresentation() {
        petInput?.cancel()
        for child in childWindows ?? [] {
            removeChildWindow(child)
            child.orderOut(nil)
        }
        // orderOut alone is insufficient: activation or a queued pocket update
        // can reorder the panel. Remove its drawing and input until the handoff.
        contentView = nil
        petInput = nil
        ignoresMouseEvents = true
        orderOut(nil)
    }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        // Only the desktop pet can extend its invisible speech margin above a display.
        // Ordinary pocket and onboarding windows retain AppKit's constraints.
        if petInput != nil { return frameRect }
        return super.constrainFrameRect(frameRect, to: screen)
    }
    override func sendEvent(_ event: NSEvent) {
        if InteractionTrace.enabled && (event.type == .leftMouseDown || event.type == .leftMouseUp) {
            let hit = contentView.flatMap { $0.hitTest($0.convert(event.locationInWindow, from: nil)) }
            InteractionTrace.record("panel event=\(event.type.rawValue) point=\(event.locationInWindow) frame=\(frame) petInput=\(petInput != nil) key=\(isKeyWindow) hit=\(hit.map { String(describing: type(of: $0)) } ?? "none")")
        }
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
    private var welcomeSession: WelcomeWindowSession?
    private let hotkey = PetHotkey()
    private lazy var tools = ToolHub()
    private var statusItem: NSStatusItem?
    private var careClock: Task<Void, Never>?
    private var desktopVisibility: DesktopVisibilityController?
    private var pendingWelcome = false
    let pet = PetModel(preferences: CommandLine.arguments.contains("--render-preview") ? nil : SociusStorage.preferences)
    private lazy var edgeDock = EdgeDockController(model: pet, automaticSizing: true)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if CommandLine.arguments.contains("--render-preview") || CommandLine.arguments.contains("--render-icon") {
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
            let width: CGFloat = CommandLine.arguments.contains("--render-icon") ? 1024 : toolName == nil ? 1000 : toolName == "Home" ? 380 : 420
            let height: CGFloat = CommandLine.arguments.contains("--render-icon") ? 1024 : toolName == nil ? 740 : toolName == "Home" ? 350 : previewHub.toolHeight
            let view = Group {
                if CommandLine.arguments.contains("--render-icon") { SociusIconView() }
                else if CommandLine.arguments.contains("--welcome") { WelcomeView(model: pet, finish: {}) }
                else if toolName == "Home" { PocketView(model: pet, close: {}, nativePopover: true, hub: previewHub) }
                else if toolName != nil { PocketToolView(hub: previewHub, pet: pet, back: {}, close: {}) }
                else { PlaygroundView(model: pet, presence: edgeDock) }
            }.frame(width: width, height: height)
            let host = NSHostingView(rootView: view)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height), styleMask: [.borderless], backing: .buffered, defer: false)
            window.isOpaque = false; window.backgroundColor = .clear
            window.contentView = host
            window.orderFrontRegardless()
            host.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            if let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                host.cacheDisplay(in: host.bounds, to: bitmap)
                if let png = bitmap.representation(using: .png, properties: [:]) {
                    try? png.write(to: URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(CommandLine.arguments.contains("--render-icon") ? "build/AppIcon.png" : toolName != nil ? "build/tool-preview.png" : CommandLine.arguments.contains("--sleeping") ? "build/sleep-preview.png" : CommandLine.arguments.contains("--pocket") ? "build/pocket-preview.png" : "build/interaction-preview.png"))
                }
            }
            window.orderOut(nil)
            NSApp.terminate(nil)
            return
        }
        let panel = PetPanel(contentRect: NSRect(x: 0, y: 0, width: 240, height: 270), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.level = .floating; panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenPrimary]
        panel.isMovableByWindowBackground = false; panel.hidesOnDeactivate = false
        if let screen = NSScreen.main { panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.maxX - 285, y: screen.visibleFrame.minY + 40)) }
        petPanel = panel
        edgeDock.start(window: panel)
        let visibility = DesktopVisibilityController(window: panel, model: pet, presence: edgeDock, hub: tools)
        visibility.changed = { [weak self] suppressed in
            guard let self else { return }
            if suppressed { welcome?.orderOut(nil) }
            else if !NSApp.isHidden {
                if pendingWelcome { pendingWelcome = false; showWelcome() }
                else { welcome?.orderFrontRegardless() }
            }
        }
        desktopVisibility = visibility
        visibility.start()
        pet.appearanceChanged = { [weak self] in
            guard let self else { return }
            edgeDock.resizeForScreen(welcome?.screen)
        }
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
            menu.addItem(withTitle: "Developer dashboard", action: #selector(showStudio), keyEquivalent: "")
        }
        menu.addItem(withTitle: "Bring pet back", action: #selector(bringBack), keyEquivalent: "")
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        menu.addItem(withTitle: "Show introduction…", action: #selector(showWelcome), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Socius", action: #selector(quit), keyEquivalent: "q")
        for entry in menu.items { entry.target = self }
        item.menu = menu; statusItem = item
        if let flag = CommandLine.arguments.firstIndex(of: "--tool"), CommandLine.arguments.indices.contains(flag + 1),
           let tool = PocketTool(rawValue: CommandLine.arguments[flag + 1]) { attachDesktopPet(); if !pet.desktopSuppressed { panel.orderFrontRegardless() }; showTool(tool) }
        else if CommandLine.arguments.contains("--onboarding") || !SociusStorage.preferences.bool(forKey: "didWelcomePet") {
            showWelcome()
        } else {
            attachDesktopPet()
            edgeDock.beginIdle()
            if !pet.desktopSuppressed { panel.orderFrontRegardless() }
            if CommandLine.arguments.contains("--developer") { showStudio() }
        }
    }
    func applicationDidBecomeActive(_ notification: Notification) { tools.layouts.refreshAccess() }
    func applicationDidHide(_ notification: Notification) { welcomeSession?.cancel() }
    func applicationDidUnhide(_ notification: Notification) {
        if !SociusStorage.preferences.bool(forKey: "didWelcomePet") { showWelcome() }
        else if !pet.desktopSuppressed { petPanel?.orderFrontRegardless() }
    }
    func applicationDidChangeScreenParameters(_ notification: Notification) { edgeDock.screenChanged() }
    private func attachDesktopPet() {
        guard let panel = petPanel, !pet.onboardingActive else { return }
        let studioAction: (() -> Void)? = CommandLine.arguments.contains("--developer") ? { [weak self] in self?.showStudio() } : nil
        panel.contentView = PetHostingView(rootView: DesktopPetView(model: pet, presence: edgeDock, openStudio: studioAction, hub: tools))
        panel.ignoresMouseEvents = false
    }
    func showTool(_ tool: PocketTool) {
        guard !pet.onboardingActive, !pet.desktopSuppressed else { return }
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
        guard welcome == nil, !pet.recordingShortcut, !pet.desktopSuppressed, let panel = petPanel else { return }
        let point = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) else { return }
        tools.dismissRequest += 1
        edgeDock.summon(at: point, on: screen)
        panel.orderFrontRegardless()
    }
    @objc func showSettings() { showTool(.settings) }
    @objc private func showWelcome() {
        guard !pet.desktopSuppressed else { pendingWelcome = true; return }
        if let welcome { welcome.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        // Screen 1 is the primary display, not the display of the focused window.
        guard let screen = NSScreen.screens.first else { attachDesktopPet(); edgeDock.beginIdle(); petPanel?.orderFrontRegardless(); return }
        pet.onboardingActive = true
        tools.dismissRequest += 1
        tools.openRequest = 0
        tools.showingTool = false
        pet.cancelActivity()
        if let panel = petPanel {
            edgeDock.repositionHome(panel.frame)
            panel.suspendDesktopPresentation()
        }
        studio?.orderOut(nil)
        edgeDock.resizeForScreen(screen)
        edgeDock.menuOpen = true
        petPanel?.orderOut(nil)
        let window = PetPanel(contentRect: screen.visibleFrame, styleMask: [.borderless, .closable], backing: .buffered, defer: false)
        window.isOpaque = false; window.backgroundColor = .clear
        window.level = .floating; window.isReleasedWhenClosed = false
        let session = WelcomeWindowSession(window: window) { [weak self, weak window] completed in
            guard let self, let window, welcome === window else { return }
            finishWelcome(completed: completed)
        }
        welcomeSession = session
        window.contentView = NSHostingView(rootView: WelcomeView(model: pet,
            finish: { [weak session] in session?.complete() },
            cancel: { [weak session] in session?.cancel() }))
        welcome = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if welcome != nil || !SociusStorage.preferences.bool(forKey: "didWelcomePet") { showWelcome() }
        else { bringBack() }
        return false
    }
    private func finishWelcome(completed: Bool) {
        guard let welcome else { return }
        if completed { SociusStorage.preferences.set(true, forKey: "didWelcomePet") }
        pet.onboardingActive = false
        attachDesktopPet()
        // Match the onboarding sprite exactly. DesktopPetView's 70/140/40
        // stack puts the pet center 120 points above its 270-point panel bottom.
        if let panel = petPanel {
            edgeDock.repositionHome(CGRect(x: welcome.frame.midX - panel.frame.width / 2,
                y: welcome.frame.midY - pet.metrics.centerFromBottom, width: panel.frame.width, height: panel.frame.height))
            if !NSApp.isHidden, !pet.desktopSuppressed { panel.orderFrontRegardless(); panel.displayIfNeeded() }
        }
        welcome.orderOut(nil)
        welcome.contentView = nil
        self.welcome = nil
        welcomeSession = nil
        edgeDock.menuOpen = false
        if pet.desktopSuppressed { edgeDock.beginIdle() } else { edgeDock.simulateIdle() }
    }
    @objc func showStudio() {
        guard !pet.onboardingActive, !pet.desktopSuppressed, CommandLine.arguments.contains("--developer") else { return }
        if studio == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 740), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "Socius · Developer dashboard"
            window.titlebarAppearsTransparent = true
            window.backgroundColor = NSColor(red: 0.96, green: 0.95, blue: 0.91, alpha: 1)
            window.minSize = NSSize(width: 420, height: 580)
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: PlaygroundView(model: pet, presence: edgeDock, replayOnboarding: { [weak self] in self?.showWelcome() }, openPocket: { [weak self] in self?.tools.openRequest += 1 }, returnPet: { [weak self] in self?.bringBack() }, closePocket: { [weak self] in self?.tools.dismissRequest += 1 }))
            window.center(); studio = window
        }
        studio?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    @objc func bringBack() {
        guard !pet.onboardingActive, !pet.desktopSuppressed else { return }
        if let screen = NSScreen.main, let panel = petPanel {
            edgeDock.repositionHome(CGRect(x: screen.visibleFrame.maxX - 285, y: screen.visibleFrame.minY + 40, width: panel.frame.width, height: panel.frame.height))
        }
        petPanel?.orderFrontRegardless()
    }
    func applicationWillTerminate(_ notification: Notification) {
        careClock?.cancel()
        desktopVisibility?.stop()
        hotkey.stop()
        edgeDock.stop()
        tools.cyclop.stop()
        tools.store.stop()
    }
    @objc func quit() { NSApp.terminate(nil) }
}
