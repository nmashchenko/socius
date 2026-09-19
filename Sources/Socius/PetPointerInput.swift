import AppKit
import SwiftUI

/// Supplies the pet's hit region without competing with SwiftUI's drop/context-menu handlers.
struct PetPointerInput: NSViewRepresentable {
    let presence: EdgeDockController
    let clicked: () -> Void
    let dragBegan: () -> Void

    func makeNSView(context: Context) -> PetPointerRegion { PetPointerRegion() }
    func updateNSView(_ view: PetPointerRegion, context: Context) {
        view.presence = presence
        view.clicked = clicked
        view.dragBegan = dragBegan
    }
    static func dismantleNSView(_ view: PetPointerRegion, coordinator: ()) { view.cancel() }
}

final class PetPointerRegion: NSView {
    weak var presence: EdgeDockController?
    var clicked: () -> Void = {}
    var dragBegan: () -> Void = {}
    private var pressLocation: CGPoint?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        (window as? PetPanel)?.petInput = self
        if window == nil { cancel() }
    }

    /// Own the entire left-button sequence, including the final release sample.
    /// Only the down event is hit-tested; dragging continues outside the original view/window.
    func handle(_ event: NSEvent) -> Bool {
        guard let presence, let window else { return false }
        switch event.type {
        case .leftMouseDown:
            guard event.window === window, !event.modifierFlags.contains(.control),
                  visibleRect.contains(convert(event.locationInWindow, from: nil)) else { return false }
            pressLocation = screenLocation(of: event)
            presence.pressPet()
        case .leftMouseDragged:
            guard let pressLocation else { return false }
            let point = screenLocation(of: event)
            if !presence.dragging && hypot(point.x - pressLocation.x, point.y - pressLocation.y) >= 4 {
                dragBegan()
                presence.beginUserDrag(at: pressLocation)
            }
            presence.dragPet(to: point)
        case .leftMouseUp:
            guard pressLocation != nil else { return false }
            pressLocation = nil
            let wasDragging = presence.dragging
            if wasDragging {
                presence.dragPet(to: screenLocation(of: event))
                presence.endUserDrag()
            }
            presence.releasePet()
            if !wasDragging { clicked() }
        default:
            return false
        }
        return true
    }

    private func screenLocation(of event: NSEvent) -> CGPoint {
        // Quartz events retain their screen position even when the window has moved
        // since the event was queued. AppKit's screen coordinates have the opposite Y axis.
        if let point = event.cgEvent?.location, let screen = NSScreen.screens.first {
            return CGPoint(x: point.x, y: screen.frame.maxY - point.y)
        }
        return window?.convertPoint(toScreen: event.locationInWindow) ?? event.locationInWindow
    }

    func cancel() {
        guard pressLocation != nil else { return }
        pressLocation = nil
        presence?.endUserDrag()
        presence?.releasePet()
    }
}
