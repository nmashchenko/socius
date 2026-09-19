import AppKit
import SwiftUI

/// A fixed transparent host lets SwiftUI morph the visible pocket without resizing AppKit chrome.
struct AnchoredPocket: NSViewRepresentable {
    @Binding var isPresented: Bool
    let model: PetModel
    let hub: ToolHub

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> PocketAnchorView { PocketAnchorView() }
    func updateNSView(_ view: PocketAnchorView, context: Context) {
        context.coordinator.dismiss = { isPresented = false }
        if hub.store.isChoosingFiles { context.coordinator.suspend(); return }
        if isPresented {
            view.didAttach = { [weak coordinator = context.coordinator, weak view] in
                if let view { coordinator?.show(from: view, model: model, hub: hub) }
            }
            context.coordinator.show(from: view, model: model, hub: hub)
        } else { view.didAttach = nil; context.coordinator.hide() }
    }
    static func dismantleNSView(_ view: PocketAnchorView, coordinator: Coordinator) { view.didAttach = nil; coordinator.hide() }

    final class Coordinator {
        var dismiss: () -> Void = {}
        private var panel: PetPanel?
        private var localMonitor: Any?
        private var globalMonitor: Any?
        private var choosingFiles: (() -> Bool)?
        private var visibleFrame: (() -> CGRect)?

        func show(from anchor: NSView, model: PetModel, hub: ToolHub) {
            if let panel {
                if !panel.isVisible { panel.ignoresMouseEvents = false; panel.makeKeyAndOrderFront(nil) }
                return
            }
            guard panel == nil, let parent = anchor.window else { return }
            let rect = parent.convertToScreen(anchor.convert(anchor.bounds, to: nil))
            let screen = parent.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? rect
            let left = rect.midX > screen.midX
            let size = CGSize(width: 460, height: 490)
            let x = left ? rect.minX - size.width + 8 : rect.maxX - 8
            let y = min(screen.maxY - size.height, max(screen.minY, rect.midY - size.height / 2))
            let window = PetPanel(contentRect: CGRect(origin: CGPoint(x: min(screen.maxX - size.width, max(screen.minX, x)), y: y), size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            window.isOpaque = false; window.backgroundColor = .clear; window.hasShadow = false
            window.hidesOnDeactivate = false; window.isReleasedWhenClosed = false
            window.acceptsMouseMovedEvents = true
            window.animationBehavior = .none; window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.contentView = PetHostingView(rootView:
                PocketView(model: model, close: { [weak self] in self?.dismiss() }, nativePopover: true, hub: hub)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: left ? .trailing : .leading)
                    .padding(16)
                    .environment(\.pocketAttachedOnRight, left)
            )
            panel = window
            choosingFiles = { hub.store.isChoosingFiles }
            visibleFrame = { [weak window] in
                guard let window else { return .zero }
                let width: CGFloat = hub.showingTool ? 420 : 340
                let height: CGFloat = hub.showingTool ? hub.toolHeight : hub.pocketHomeHeight
                return CGRect(x: window.frame.minX + (left ? size.width - 16 - width : 16),
                              y: window.frame.midY - height / 2, width: width, height: height).insetBy(dx: -9, dy: -4)
            }
            parent.addChildWindow(window, ordered: .above)
            window.makeKeyAndOrderFront(nil)
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown, .mouseMoved]) { [weak self, weak parent] event in
                let consumed = MainActor.assumeIsolated {
                    guard let self, self.choosingFiles?() != true else { return false }
                    if event.type == .mouseMoved { self.updateHitRegion(); return false }
                    if event.type == .keyDown && event.keyCode == 53 { self.dismiss(); return true }
                    // The pet owns its click/drag sequence and closes this pocket when a drag starts.
                    if event.type != .keyDown && event.window !== self.panel && event.window !== parent { self.dismiss() }
                    return false
                }
                return consumed ? nil : event
            }
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .mouseMoved]) { [weak self] event in
                let moved = event.type == .mouseMoved
                Task { @MainActor in
                    guard self?.choosingFiles?() != true else { return }
                    if moved { self?.updateHitRegion(); return }
                    self?.dismiss()
                }
            }
        }
        func suspend() { panel?.orderOut(nil) }
        private func updateHitRegion() {
            // The invisible margin must not intercept clicks meant for other desktop apps.
            panel?.ignoresMouseEvents = !(visibleFrame?().contains(NSEvent.mouseLocation) ?? false)
        }
        func hide() {
            if let localMonitor { NSEvent.removeMonitor(localMonitor) }
            if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
            localMonitor = nil; globalMonitor = nil
            if let panel { panel.parent?.removeChildWindow(panel) }
            panel?.orderOut(nil); panel = nil
            choosingFiles = nil
            visibleFrame = nil
        }
    }
}

final class PocketAnchorView: NSView {
    var didAttach: (() -> Void)?
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { didAttach?() }
    }
}
