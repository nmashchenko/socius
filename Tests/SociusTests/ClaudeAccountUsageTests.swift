import Foundation
import Testing
@testable import Socius

@MainActor struct ClaudeAccountUsageTests {
    @Test func accountWindowsKeepSessionWeeklyAndModelLimitsSeparate() throws {
        let input = Data(#"{"five_hour":{"utilization":10,"resets_at":"2026-09-22T18:00:00Z"},"seven_day":{"utilization":44,"resets_at":"2026-09-22T18:00:00.000Z"},"seven_day_fable":{"utilization":48,"resets_at":"2026-09-22T18:00:00Z"},"seven_day_opus":null}"#.utf8)
        let windows = try UsageParser.claudeAccount(input)
        #expect(windows.map(\.used) == [10, 44, 48])
        #expect(windows.map(\.remaining) == [90, 56, 52])
        #expect(windows.allSatisfy { $0.resetsAt != nil })
    }
    @Test func missingAccountWindowsAreUnknownInsteadOfZero() throws {
        #expect(try UsageParser.claudeAccount(Data(#"{"seven_day":null,"five_hour":{"utilization":-1}}"#.utf8)).isEmpty)
    }
}
