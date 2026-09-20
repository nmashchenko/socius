import AppKit
import SwiftUI
import Testing
@testable import CyclopTools

@MainActor @Suite(.serialized) struct SnippetInputTests {
    @Test func returnCommitsCurrentEditorTextAndEscapeCancels() async throws {
        var value = ""
        var saved: String?
        var cancelled = false
        let host = NSHostingView(rootView: SnippetInput(placeholder: "Text",
            text: Binding(get: { value }, set: { value = $0 }), focused: false,
            onFocus: {}, submit: { saved = value }, cancel: { cancelled = true }).frame(width: 220, height: PocketMetrics.controlHeight))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 220, height: 34), styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        defer { window.orderOut(nil) }
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
        func field(in view: NSView) -> NSTextField? {
            if let field = view as? NSTextField { return field }
            return view.subviews.compactMap { field(in: $0) }.first
        }
        let input = try #require(field(in: host))
        let delegate = try #require(input.delegate)
        let editor = NSTextView()
        editor.string = "Typed right before Return"
        #expect(delegate.control?(input, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:))) == true)
        #expect(saved == editor.string)
        #expect(delegate.control?(input, textView: editor, doCommandBy: #selector(NSResponder.cancelOperation(_:))) == true)
        #expect(cancelled)
        #expect(delegate.control?(input, textView: editor, doCommandBy: #selector(NSResponder.insertTab(_:))) == false)
        #expect(input.superview?.frame.height == PocketMetrics.controlHeight)
    }

    @Test func failedSaveDoesNotPublishAnUnsavedSnippet() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("not a directory".utf8).write(to: directory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SnippetStore(file: directory.appendingPathComponent("snippets.json"))
        #expect(!store.add(label: "Keep my draft", text: "Unsaved text"))
        #expect(store.items.isEmpty)
        #expect(store.writeError != nil)
    }
}
