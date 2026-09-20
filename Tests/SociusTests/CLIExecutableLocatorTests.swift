import Foundation
import Testing
@testable import Socius

struct CLIExecutableLocatorTests {
    @Test func guiLaunchFindsVersionManagedClaudeWithoutShellPath() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        func install(_ version: String) throws -> URL {
            let executable = home.appendingPathComponent(".nvm/versions/node/\(version)/bin/claude")
            try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
            return executable
        }
        _ = try install("v9.0.0")
        let newest = try install("v22.0.0")
        #expect(CLIExecutableLocator.claude(home: home, path: "", systemDirectories: []) == newest)
        #expect(CLIExecutableLocator.runtimePath(for: newest).hasPrefix(newest.deletingLastPathComponent().path + ":"))
    }
    @Test func nonExecutableInstallDoesNotMasqueradeAsAvailableCLI() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let directory = home.appendingPathComponent(".local/bin")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        try Data().write(to: directory.appendingPathComponent("claude"))
        #expect(CLIExecutableLocator.claude(home: home, path: "", systemDirectories: []) == nil)
    }
}
