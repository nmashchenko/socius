import SwiftUI
import AppKit
import Testing
@testable import CyclopTools

@MainActor struct PocketNoteEditorTests {
    @Test func typingKeepsScrollbarGutterAbsentAndUpdatesBinding() async throws {
        var text = ""
        let binding = Binding<String>(get: { text }, set: { text = $0 })
        let host = NSHostingView(rootView: PocketNoteEditor(text: binding, noteID: UUID(),
            wantsKeyboard: .constant(false), editable: true).frame(width: 200, height: 120))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 200, height: 120),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        defer { window.orderOut(nil) }
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(80))
        func findScroll(_ view: NSView) -> NSScrollView? {
            if let scroll = view as? NSScrollView { return scroll }
            return view.subviews.compactMap(findScroll).first
        }
        let scroll = try #require(findScroll(host))
        let editor = try #require(scroll.documentView as? NSTextView)
        let longText = Array(repeating: "A note that scrolls", count: 30).joined(separator: "\n")
        editor.insertText(longText, replacementRange: NSRange(location: 0, length: 0))
        host.layoutSubtreeIfNeeded()
        #expect(text == longText)
        #expect(!scroll.hasVerticalScroller)
        #expect(!scroll.hasHorizontalScroller)
        // macOS may override scrollerStyle based on system preferences; no gutter may be reserved.
        #expect(abs(scroll.contentSize.width - scroll.bounds.width) < 1)
        #expect(editor.frame.height > scroll.contentSize.height)
    }
}
