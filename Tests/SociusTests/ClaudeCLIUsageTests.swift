import Foundation
import Testing
@testable import Socius

struct ClaudeCLIUsageTests {
    @Test func redrawKeepsDistinctAccountWindows() {
        let raw = "\u{1b}[2J\u{1b}[HCurrent session\r\n██ 3% used\r\nResets 1:20pm (America/New_York)\r\nCurrent week (all models)\r\n████ 50% used\r\nResets Sep 22 at 2pm (America/New_York)\r\nCurrent week (Fable)\r\n████ 49% used\r\nResets Sep 22 at 2pm (America/New_York)\u{1b}[2;1H\u{1b}[2K██ 4% used"
        let windows = ClaudeCLIUsage.parse(UsageTerminal(raw).text)
        #expect(windows.map(\.used) == [4, 50, 49])
        #expect(windows.last?.name == "Current week (Fable)")
        #expect(windows.first?.reset == "Resets 1:20pm (America/New_York)")
    }
    @Test func incompleteWindowCannotBorrowNextWindowsMeter() {
        let screen = "Current session\nRefreshing…\nCurrent week (all models)\n50% used\nResets tomorrow"
        #expect(ClaudeCLIUsage.parse(screen).map(\.name) == ["Current week (all models)"])
    }
    @Test(.enabled(if: ProcessInfo.processInfo.environment["SOCIUS_LIVE_CLAUDE_USAGE"] == "1"))
    func installedCLIProvidesAccountLimits() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SociusUsageTest-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let windows = try await ClaudeCLIUsage.read(
            executable: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/claude"),
            directory: directory)
        #expect(windows.contains { $0.name == "Current session" })
        #expect(windows.contains { $0.name == "Current week (all models)" })
    }
}
