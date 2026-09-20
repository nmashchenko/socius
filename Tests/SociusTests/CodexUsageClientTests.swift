import Foundation
import Testing
@testable import Socius

@MainActor struct CodexUsageClientTests {
    private func executable(_ script: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("socius-mock-codex-\(UUID())")
        try Data(("#!/bin/sh\n" + script).utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
    }

    @Test func cancellingASilentCLIStopsPromptly() async throws {
        let url = try executable("while IFS= read -r line; do :; done\n")
        defer { try? FileManager.default.removeItem(at: url) }
        let task = Task { try await CodexUsageClient.read(executable: url, timeoutSeconds: 4) }
        try await Task.sleep(for: .milliseconds(200))
        let began = ContinuousClock.now
        task.cancel()
        do { _ = try await task.value; Issue.record("Expected cancellation") }
        catch is CancellationError { }
        catch { Issue.record("Wrong cancellation error: \(error)") }
        #expect(began.duration(to: .now) < .seconds(1))
    }

    @Test func timeoutIsReportedAsTimeout() async throws {
        let url = try executable("while IFS= read -r line; do :; done\n")
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            _ = try await CodexUsageClient.read(executable: url, timeoutSeconds: 0.2)
            Issue.record("Expected timeout")
        } catch { #expect(error.localizedDescription.contains("timed out")) }
    }
}
