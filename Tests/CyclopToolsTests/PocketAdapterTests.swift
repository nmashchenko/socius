import AppKit
import Testing
@testable import CyclopTools

@MainActor @Suite(.serialized) struct PocketAdapterTests {
    @Test func importsLegacyContentWithoutChangingOriginalFile() throws {
        try #require(Support.isPreview)
        let source = Support.file("legacy-tools.json")
        let bytes = Data(#"{"snippets":[{"title":"Greeting","text":"Hello"}],"notes":[{"id":"00000000-0000-0000-0000-000000000001","title":"Thought","text":"Keep this thought","updatedAt":100}],"shelf":[],"clipboardEnabled":false}"#.utf8)
        try bytes.write(to: source)
        let pocket = CyclopPocket(legacyFile: source)
        #expect(pocket.snippets.items.first?.label == "Greeting")
        #expect(pocket.notes.notes.first?.text == "Thought\n\nKeep this thought")
        #expect(!pocket.rememberCopies)
        #expect(try Data(contentsOf: source) == bytes)
        // A second launch cannot re-import stale legacy content over new edits.
        pocket.snippets.add(label: "New", text: "Written after migration")
        let relaunched = CyclopPocket(legacyFile: source)
        #expect(relaunched.snippets.items.first?.label == "New")
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["SOCIUS_NATIVE_PICKER_TEST"] == "1"))
    func filePickerCancellationEndsSuspension() async throws {
        try #require(Support.isPreview)
        let pocket = CyclopPocket(legacyFile: Support.file("missing-legacy.json"))
        NSApplication.shared.setActivationPolicy(.regular)
        pocket.addFiles()
        try await Task.sleep(for: .milliseconds(250))
        #expect(pocket.choosingFiles)
        let picker = try #require(pocket.panel)
        #expect(picker.allowsMultipleSelection)
        picker.cancel(nil)
        try await Task.sleep(for: .milliseconds(250))
        #expect(!pocket.choosingFiles)
    }
}
