import SwiftUI
import AppKit

struct SnippetInput: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    var focused: Bool
    let onFocus: () -> Void
    let submit: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> Container {
        let view = Container()
        view.field.delegate = context.coordinator
        view.field.target = context.coordinator
        view.field.action = #selector(Coordinator.commit)
        return view
    }
    func updateNSView(_ view: Container, context: Context) {
        context.coordinator.owner = self
        view.field.placeholderString = placeholder
        if view.field.stringValue != text { view.field.stringValue = text }
        if focused {
            DispatchQueue.main.async {
                guard let window = view.window, window.isKeyWindow, view.field.currentEditor() == nil else { return }
                window.makeFirstResponder(view.field)
            }
        }
    }
    final class Container: NSView {
        let field = NSTextField(string: "")
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
            field.frame = NSRect(x: 8, y: floor((bounds.height - 18) / 2), width: max(0, bounds.width - 16), height: 18)
        }
    }
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var owner: SnippetInput
        init(_ owner: SnippetInput) { self.owner = owner }
        func controlTextDidChange(_ notification: Notification) {
            if let field = notification.object as? NSTextField { owner.text = field.stringValue }
        }
        func controlTextDidBeginEditing(_ notification: Notification) { owner.onFocus() }
        @MainActor @objc func commit() { owner.submit() }
    }
}
