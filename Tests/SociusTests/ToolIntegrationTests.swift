import Foundation
import Testing
@testable import Socius

@MainActor @Suite struct ToolIntegrationTests {
    @Test func codexUsesNamedBucketAndCorrectShortWindowLabels() throws {
        let windows = try UsageParser.codex(Data(#"{"result":{"rateLimits":{"primary":{"usedPercent":99}},"rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":25,"windowDurationMins":15,"resetsAt":1999999999},"secondary":{"usedPercent":42,"windowDurationMins":10080}}}}}"#.utf8))
        #expect(windows.count == 2)
        #expect(windows[0].name == "15-minute allowance")
        #expect(windows[0].remaining == 75)
        #expect(windows[1].name == "7-day allowance")
    }
    @Test func missingAndMalformedAllowancesAreNotReportedAsZero() throws {
        #expect(try UsageParser.claude(Data(#"{"rate_limits":{"five_hour":{"used_percentage":1788483600}}}"#.utf8)).isEmpty)
        #expect(try UsageParser.codex(Data(#"{"result":{"rateLimits":{"primary":null}}}"#.utf8)).isEmpty)
        #expect(throws: (any Error).self) { try UsageParser.codex(Data(#"{"error":{"message":"Sign in first"}}"#.utf8)) }
    }
    @Test func claudeShowsUsedRemainingAndExpiredWindows() throws {
        let windows = try UsageParser.claude(Data(#"{"rate_limits":{"five_hour":{"used_percentage":32.5,"resets_at":1},"spend_limit":{"used_percentage":105}}}"#.utf8))
        #expect(windows.count == 2)
        #expect(windows[0].remaining == 67.5)
        #expect(windows[0].expired)
        #expect(windows[1].remaining == 0)
    }
    @Test func layoutRestoresFractionsOnDifferentDisplayAndClampsOffscreen() {
        let saved = SavedWindow(bundleID: "test", appName: "Test", title: "Window", index: 0, screenID: 1, x: 0.5, y: 0, width: 0.5, height: 1)
        #expect(LayoutGeometry.restored(saved, on: CGRect(x: -1920, y: 25, width: 1920, height: 1000)) == CGRect(x: -960, y: 25, width: 960, height: 1000))
        var oversized = saved; oversized.x = 4; oversized.y = -3; oversized.width = 2
        let rect = LayoutGeometry.restored(oversized, on: CGRect(x: 0, y: 0, width: 1000, height: 700))
        #expect(rect == CGRect(x: 0, y: 0, width: 1000, height: 700))
    }
    @Test func shellQuoteKeepsWhitespaceAndApostrophesLiteral() {
        #expect(ClaudeUsageBridge.shellQuote("a'b $(test)") == "'a'\\''b $(test)'")
    }
    @Test func claudeBridgePreservesAndRestoresSettings() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("SociusBridgeTests-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let settings = dir.appendingPathComponent("settings.json")
        try Data(#"{"theme":"dark","statusLine":{"type":"command","command":"echo 'hello'","padding":2}}"#.utf8).write(to: settings)
        try ClaudeUsageBridge.install(directory: dir, settingsURL: settings, executable: URL(fileURLWithPath: "/tmp/a folder/Socius"))
        var connected = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as? [String: Any])
        let line = try #require(connected["statusLine"] as? [String: Any])
        #expect(line["padding"] as? Int == 2)
        #expect((line["command"] as? String)?.contains("--forward") == true)
        // An unrelated setting changed after installation must survive disconnect.
        connected["theme"] = "light"
        try JSONSerialization.data(withJSONObject: connected).write(to: settings)
        try ClaudeUsageBridge.uninstall(directory: dir)
        let restored = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as? [String: Any])
        #expect(restored["theme"] as? String == "light")
        #expect((restored["statusLine"] as? [String: Any])?["command"] as? String == "echo 'hello'")
    }
    @Test func codexHandshakeReadsLimitsWithoutStartingAConversation() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("SociusRPCTests-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let executable = dir.appendingPathComponent("mock-codex")
        let script = #"""
        #!/bin/sh
        IFS= read -r initialization
        case "$initialization" in *'"initialize"'*) ;; *) exit 1 ;; esac
        printf '%s\n' '{"id":1,"result":{}}'
        IFS= read -r ready
        IFS= read -r request
        case "$request" in *'rateLimits'*'read'*) ;; *) exit 2 ;; esac
        printf '%s\n' '{"method":"unrelated/notification"}' '{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":12,"windowDurationMins":300}}}}'
        IFS= read -r finished
        """#
        try Data(script.utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let result = try await CodexUsageClient.read(executable: executable, timeoutSeconds: 2)
        #expect(try UsageParser.codex(result).first?.used == 12)
    }
    @Test(.enabled(if: ProcessInfo.processInfo.environment["SOCIUS_LIVE_USAGE_TEST"] == "1"))
    func liveCodexUsageConnection() async throws {
        let executable = try #require(CodexUsageClient.executable())
        let result = try await CodexUsageClient.read(executable: executable)
        let windows = try UsageParser.codex(result)
        #expect(!windows.isEmpty)
    }
}
