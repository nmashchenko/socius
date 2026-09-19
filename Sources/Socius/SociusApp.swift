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
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class PetHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private var petPanel: PetPanel?
    private var studio: NSWindow?
    private lazy var tools = ToolHub()
    private var statusItem: NSStatusItem?
    private var careClock: Task<Void, Never>?
    let prototype = PetPrototype()
    private lazy var edgeDock = EdgeDockController(model: prototype)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if CommandLine.arguments.contains("--render-preview") {
            if CommandLine.arguments.contains("--sleeping") { prototype.sleep() }
            if CommandLine.arguments.contains("--pocket") { prototype.panelOpen = true }
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
                if toolName == "Home" { PocketView(model: prototype, close: {}, nativePopover: true, hub: previewHub) }
                else if toolName != nil { PocketToolView(hub: previewHub, pet: prototype, back: {}, close: {}) }
                else { PlaygroundView(model: prototype) }
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
        panel.isMovableByWindowBackground = true; panel.hidesOnDeactivate = false
        let studioAction: (() -> Void)? = CommandLine.arguments.contains("--developer") ? { [weak self] in self?.showStudio() } : nil
        panel.contentView = PetHostingView(rootView: DesktopPetView(model: prototype, presence: edgeDock, openStudio: studioAction, hub: tools))
        if let screen = NSScreen.main { panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.maxX - 285, y: screen.visibleFrame.minY + 40)) }
        panel.orderFrontRegardless(); petPanel = panel
        edgeDock.start(window: panel)
        tools.cyclop.start()
        careClock = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
                self?.prototype.tick()
            }
        }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "Socius")
        let menu = NSMenu()
        if CommandLine.arguments.contains("--developer") {
            menu.addItem(withTitle: "Interaction playground", action: #selector(showStudio), keyEquivalent: "")
        }
        menu.addItem(withTitle: "Bring Mochi back", action: #selector(bringBack), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Socius", action: #selector(quit), keyEquivalent: "q")
        for entry in menu.items { entry.target = self }
        item.menu = menu; statusItem = item
        if let flag = CommandLine.arguments.firstIndex(of: "--tool"), CommandLine.arguments.indices.contains(flag + 1),
           let tool = PocketTool(rawValue: CommandLine.arguments[flag + 1]) { showTool(tool) }
        else if CommandLine.arguments.contains("--developer") { showStudio() }
    }
    func applicationDidChangeScreenParameters(_ notification: Notification) { edgeDock.screenChanged() }
    func showTool(_ tool: PocketTool) {
        guard prototype.toolsAvailable else { return }
        tools.selected = tool
        tools.store.notice = nil
        tools.showingTool = true
        tools.openRequest += 1
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
            window.contentView = NSHostingView(rootView: PlaygroundView(model: prototype, presence: edgeDock, openTool: { [weak self] in self?.showTool($0) }))
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
    @objc func quit() { edgeDock.stop(); tools.cyclop.stop(); tools.store.stop(); NSApp.terminate(nil) }
}
