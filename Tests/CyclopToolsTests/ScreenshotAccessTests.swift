import Foundation
import Testing
@testable import CyclopTools

@MainActor @Suite(.serialized) struct ScreenshotAccessTests {
    @Test func renamedFolderStopsWatchingAndReportsLostAccess() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let original = base.appendingPathComponent("watched")
        try FileManager.default.createDirectory(at: original, withIntermediateDirectories: true)
        let watcher = ScreenshotFolderWatcher()
        var errors = 0
        watcher.onAccessError = { errors += 1 }
        defer { watcher.stop(); try? FileManager.default.removeItem(at: base) }
        #expect(watcher.start(at: original))
        try FileManager.default.moveItem(at: original, to: base.appendingPathComponent("renamed"))
        try await Task.sleep(for: .milliseconds(350))
        #expect(watcher.activeFolder == nil)
        #expect(errors == 1)
    }

    @Test func aDeletedFilenameCanBeCollectedAgain() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let watcher = ScreenshotFolderWatcher()
        var received = 0
        watcher.onImage = { _ in received += 1 }
        defer { watcher.stop(); try? FileManager.default.removeItem(at: folder) }
        #expect(watcher.start(at: folder))
        let file = folder.appendingPathComponent("Screenshot.png")
        try Data("first image".utf8).write(to: file)
        try await Task.sleep(for: .milliseconds(500))
        try FileManager.default.removeItem(at: file)
        try await Task.sleep(for: .milliseconds(250))
        try Data("second image".utf8).write(to: file)
        try await Task.sleep(for: .milliseconds(500))
        #expect(received == 2)
    }

    @Test func watcherRejectsMissingFolderAndStartsAfterItExists() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let watcher = ScreenshotFolderWatcher()
        defer {
            watcher.stop()
            try? FileManager.default.removeItem(at: folder)
        }
        #expect(!watcher.start(at: folder))
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        #expect(watcher.start(at: folder))
    }
    @Test func stopUpdatesStatusAndCancelsPendingScreenshots() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let watcher = ScreenshotFolderWatcher()
        var states: [URL?] = []
        var received = 0
        watcher.onStateChanged = { states.append(watcher.activeFolder) }
        watcher.onImage = { _ in received += 1 }
        defer { watcher.stop(); try? FileManager.default.removeItem(at: folder) }
        #expect(watcher.start(at: folder))
        #expect(watcher.activeFolder == folder)
        try Data("image placeholder".utf8).write(to: folder.appendingPathComponent("Screenshot.png"))
        try await Task.sleep(for: .milliseconds(80))
        watcher.stop()
        try await Task.sleep(for: .milliseconds(400))
        #expect(watcher.activeFolder == nil)
        #expect(states.contains { $0 == folder })
        #expect(states.last! == nil)
        #expect(received == 0)
    }

}
