import SwiftUI
import AppKit

/// Own the scroll view so typing cannot restore SwiftUI's legacy scrollbar gutter.
struct PocketNoteEditor: NSViewRepresentable {
    @Binding var text: String
    let noteID: UUID?
    @Binding var wantsKeyboard: Bool
    let editable: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.scrollerStyle = .overlay
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        let editor = NSTextView(frame: .zero)
        editor.isRichText = false
        editor.allowsUndo = true
        editor.drawsBackground = false
        editor.font = .systemFont(ofSize: 12.5)
        editor.textColor = NSColor(red: 0.23, green: 0.28, blue: 0.24, alpha: 1)
        editor.insertionPointColor = editor.textColor!
        editor.textContainerInset = NSSize(width: 0, height: 0)
        editor.textContainer?.lineFragmentPadding = 0
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        editor.delegate = context.coordinator
        scroll.documentView = editor
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let editor = scroll.documentView as? NSTextView else { return }
        context.coordinator.owner = self
        if context.coordinator.noteID != noteID {
            editor.undoManager?.removeAllActions()
            context.coordinator.noteID = noteID
        }
        if editor.string != text { editor.string = text }
        editor.isEditable = editable
        editor.isSelectable = editable
        if wantsKeyboard && editable {
            DispatchQueue.main.async {
                guard let window = editor.window, window.isKeyWindow,
                      window.firstResponder !== editor else { return }
                window.makeFirstResponder(editor)
            }
        }
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var owner: PocketNoteEditor
        var noteID: UUID?
        init(_ owner: PocketNoteEditor) { self.owner = owner }
        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            owner.text = editor.string
        }
        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard selector == #selector(NSResponder.cancelOperation(_:)) else { return false }
            owner.wantsKeyboard = false
            textView.window?.makeFirstResponder(nil)
            return true
        }
    }
}
