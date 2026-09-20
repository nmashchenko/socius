import SwiftUI
import AppKit

struct SnippetInput: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    var focused: Bool
    let onFocus: () -> Void
    let submit: () -> Void
    var cancel: () -> Void = {}
    var focusGroup: UUID?
    var onBlur: () -> Void = {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> Container {
        let view = Container()
        view.field.delegate = context.coordinator
        return view
    }
    func updateNSView(_ view: Container, context: Context) {
        context.coordinator.owner = self
        view.field.placeholderString = placeholder
        if view.field.stringValue != text { view.field.stringValue = text }
        view.field.setAccessibilityLabel(placeholder)
        view.field.identifier = focusGroup.map { NSUserInterfaceItemIdentifier($0.uuidString) }
        let requestFocus = focused && !view.requestedFocus
        view.requestedFocus = focused
        if requestFocus {
            DispatchQueue.main.async {
                guard context.coordinator.owner.focused, let window = view.window,
                      window.isKeyWindow, view.field.currentEditor() == nil else { return }
                window.makeFirstResponder(view.field)
            }
        }
    }
    final class Container: NSView {
        let field = NSTextField(string: "")
        var requestedFocus = false
        override init(frame: NSRect) {
            super.init(frame: frame)
            field.isBordered = false
            field.drawsBackground = false
            field.focusRingType = .none
            field.font = .systemFont(ofSize: 12)
            field.textColor = NSColor(red: 0.23, green: 0.28, blue: 0.24, alpha: 1)
            field.cell?.usesSingleLineMode = true
            field.cell?.isScrollable = true
            addSubview(field)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) is unsupported") }
        override func layout() {
            super.layout()
            field.frame = NSRect(x: PocketMetrics.controlInset, y: floor((bounds.height - 18) / 2), width: max(0, bounds.width - PocketMetrics.controlInset * 2), height: 18)
        }
    }
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var owner: SnippetInput
        init(_ owner: SnippetInput) { self.owner = owner }
        func controlTextDidChange(_ notification: Notification) {
            if let field = notification.object as? NSTextField { owner.text = field.stringValue }
        }
        func controlTextDidBeginEditing(_ notification: Notification) { owner.onFocus() }
        func controlTextDidEndEditing(_ notification: Notification) {
            // The next field acquires its editor after this notification. Moving
            // between a row's two fields must not commit halfway through the move.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let field = (NSApp.keyWindow?.firstResponder as? NSTextView)?.delegate as? NSTextField
                if let group = self.owner.focusGroup, field?.identifier?.rawValue == group.uuidString { return }
                self.owner.onBlur()
            }
        }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)):
                owner.text = textView.string
                owner.submit()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                owner.cancel()
                return true
            default: return false
            }
        }
    }
}
