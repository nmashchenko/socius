import AppKit
import SwiftUI

/// SwiftUI's indicator preference can still leave a legacy gutter when macOS
/// is configured to always show scrollbars. Configure the enclosing native view.
struct PocketScrollGutterFix: NSViewRepresentable {
    final class Probe: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            configure()
        }
        func configure() {
            guard let scroll = enclosingScrollView else { return }
            scroll.scrollerStyle = .overlay
            scroll.hasVerticalScroller = false
            scroll.hasHorizontalScroller = false
            scroll.drawsBackground = false
        }
    }
    func makeNSView(context: Context) -> Probe { Probe() }
    func updateNSView(_ view: Probe, context: Context) { view.configure() }
}
