import AppKit
import Testing
@testable import Socius

@MainActor @Suite struct ToolStoreTests {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("SociusTests-\(UUID())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    @Test func notesAndSnippetsSurviveRelaunchAndStaySeparate() throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = ToolStore(directory: dir)
        var note = TextItem(title: "Idea", text: "First draft")
        let saved = store.saveText(note, in: .notes)
        #expect(saved)
        note.text = "Updated draft"
        let updated = store.saveText(note, in: .notes)
        #expect(updated)
        let snippetSaved = store.saveText(TextItem(title: "Address", text: "123 Example St"), in: .snippets)
        #expect(snippetSaved)
        let restored = ToolStore(directory: dir)
        #expect(restored.data.notes.count == 1)
        #expect(restored.data.notes.first?.text == "Updated draft")
        #expect(restored.data.snippets.first?.title == "Address")
        #expect(restored.clipboard.isEmpty)
    }
    @Test func corruptedDataIsPreservedAndWritesRefused() throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("tools.json")
        let broken = Data("not valid json".utf8)
        try broken.write(to: file)
        let store = ToolStore(directory: dir)
        let saved = store.saveText(TextItem(title: "New", text: "body"), in: .notes)
        #expect(!saved)
        #expect(store.loadError != nil)
        #expect(try Data(contentsOf: file) == broken)
    }
    @Test func failedWriteDoesNotClaimAnEditSucceeded() throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = ToolStore(directory: dir)
        try FileManager.default.removeItem(at: dir)
        let saved = store.saveText(TextItem(title: "Draft", text: "Keep me"), in: .notes)
        #expect(!saved)
        #expect(store.data.notes.isEmpty)
        #expect(store.notice != nil)
    }
    @Test func clipboardDefaultMigrationRunsOnceAndPreservesLaterPause() throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        var legacy = ToolData()
        legacy.clipboardDefaultVersion = nil
        legacy.clipboardEnabled = false
        try JSONEncoder().encode(legacy).write(to: dir.appendingPathComponent("tools.json"))
        let migrated = ToolStore(directory: dir)
        #expect(migrated.data.clipboardEnabled)
        migrated.setClipboardEnabled(false)
        let relaunched = ToolStore(directory: dir)
        #expect(!relaunched.data.clipboardEnabled)
    }
    @Test func clipboardKeepsFortyAndMovesDuplicatesToFront() throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = ToolStore(directory: dir)
        for index in 0..<45 { store.record(ClipboardItem(text: "copy \(index)")) }
        #expect(store.clipboard.count == 40)
        #expect(store.clipboard.last?.text == "copy 5")
        store.record(ClipboardItem(text: "copy 12"))
        #expect(store.clipboard.count == 40)
        #expect(store.clipboard.first?.text == "copy 12")
        store.record(ClipboardItem(png: Data([1, 2, 3])))
        #expect(store.clipboard.count == 40)
        #expect(store.clipboard.first?.png == Data([1, 2, 3]))
    }
    @Test func clipboardCollectsByDefaultAndRespectsPauseAndConcealedCopies() throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let board = NSPasteboard(name: .init("SociusTests-\(UUID())"))
        defer { board.releaseGlobally() }
        let store = ToolStore(directory: dir, pasteboard: board)
        #expect(store.data.clipboardEnabled)
        store.setClipboardEnabled(false)
        board.clearContents(); board.setString("before opt-in", forType: .string); store.pollClipboard()
        #expect(store.clipboard.isEmpty)
        store.setClipboardEnabled(true)
        board.clearContents(); board.setString("public text", forType: .string); store.pollClipboard()
        #expect(store.clipboard.first?.text == "public text")
        board.clearContents(); board.setString("secret", forType: .string)
        board.setData(Data(), forType: .init("org.nspasteboard.ConcealedType")); store.pollClipboard()
        #expect(store.clipboard.count == 1)
        store.copy("own copy"); store.pollClipboard()
        #expect(store.clipboard.count == 1)
        store.setClipboardEnabled(false)
        board.clearContents(); board.setString("paused", forType: .string); store.pollClipboard()
        #expect(store.clipboard.count == 1)
    }
    @Test func screenshotScanOrdersNewestAndDoesNotReinsertRemovedFiles() throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let folder = dir.appendingPathComponent("Screenshots")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for index in 0..<25 {
            let url = folder.appendingPathComponent("shot-\(index).png")
            try Data().write(to: url)
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: Double(index + 1))], ofItemAtPath: url.path)
        }
        let store = ToolStore(directory: dir)
        store.update { $0.screenshotFolder = folder.path }
        store.scanScreenshots()
        #expect(store.data.shelf.count == 20)
        #expect(store.data.shelf.first?.url.lastPathComponent == "shot-24.png")
        store.update { $0.shelf.removeFirst() }
        store.scanScreenshots()
        #expect(store.data.shelf.count == 19)
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("shot-24.png").path))
    }
}
