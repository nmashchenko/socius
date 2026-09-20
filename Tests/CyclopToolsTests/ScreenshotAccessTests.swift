import Foundation
import Testing
@testable import CyclopTools

@MainActor @Suite struct ScreenshotAccessTests {
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
}
