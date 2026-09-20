import AppKit
import Testing
@testable import CyclopTools

@MainActor @Suite(.serialized) struct ReviewRegressionTests {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func openingAndLeavingBrokenNotesNeverOverwritesTheFile() throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("notes.json")
        let bytes = Data("unfinished external edit".utf8)
        try bytes.write(to: file)
        let notes = NoteStore(file: file)
        notes.add()
        notes.leave()
        notes.flush()
        #expect(notes.loadError != nil)
        #expect(try Data(contentsOf: file) == bytes)
    }

    @Test func notesDetectExternalChangesAndKeepUnsavedText() throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("notes.json")
        let notes = NoteStore(file: file)
        notes.add()
        let id = try #require(notes.selected)
        notes.update(id, text: "saved first")
        notes.flush()
        let external = Data("[]".utf8)
        try external.write(to: file)
        notes.update(id, text: "keep this draft")
        notes.flush()
        #expect(notes.writeError != nil)
        #expect(notes.notes.first?.text == "keep this draft")
        #expect(try Data(contentsOf: file) == external)
    }

    @Test func reorderingPreservesExternalAdditionsAndRefusesMalformedFiles() throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("snippets.json")
        let store = SnippetStore(file: file)
        store.add(label: "B", text: "two")
        store.add(label: "A", text: "one")
        let a = try #require(store.items.first)
        let external = [Snippet(label: "External", text: "three")] + store.items
        try JSONEncoder().encode(external).write(to: file)
        store.move(a, to: 1)
        #expect(store.items.map(\.label) == ["External", "B", "A"])
        let broken = Data("[".utf8)
        try broken.write(to: file)
        store.move(a, to: 1)
        #expect(store.fileBroken)
        #expect(try Data(contentsOf: file) == broken)
    }

    @Test func pausingSkipsCopiesMadeWhilePaused() async throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let store = ClipboardStore(pasteboard: board)
        store.start()
        store.stop()
        board.clearContents()
        board.setString("copied while paused", forType: .string)
        store.start()
        defer { store.stop() }
        try await Task.sleep(for: .milliseconds(800))
        #expect(store.items.isEmpty)
        board.clearContents()
        board.setString("copied after resuming", forType: .string)
        try await Task.sleep(for: .milliseconds(800))
        #expect(store.items.first?.preview == "copied after resuming")
    }

    @Test func pausingCancelsPendingUniversalClipboardImages() async throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let store = ClipboardStore(pasteboard: board)
        var images = 0
        store.onImage = { _ in images += 1 }
        store.start()
        board.declareTypes([.png], owner: nil)
        try await Task.sleep(for: .milliseconds(750))
        store.stop()
        let generation = board.changeCount
        board.setData(Data([1, 2, 3]), forType: .png)
        #expect(board.changeCount == generation)
        try await Task.sleep(for: .milliseconds(750))
        #expect(images == 0)
    }

    @Test func closingPocketCoversRevealedItems() throws {
        let pocket = CyclopPocket(legacyFile: Support.file("absent-review-legacy.json"))
        let covered = pocket.privacy.covers(.snippets)
        defer { pocket.privacy.setCovering(.snippets, covered) }
        pocket.privacy.setCovering(.snippets, true)
        pocket.privacy.reveal("snippet.test")
        #expect(!pocket.privacy.hides(.snippets, "snippet.test"))
        pocket.closePresentation()
        #expect(pocket.privacy.hides(.snippets, "snippet.test") == pocket.privacy.covers(.snippets))
        #expect(ScreenshotVault.folder.path.hasPrefix(Support.folder.path + "/"))
    }
}
