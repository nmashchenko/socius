import CyclopTools
import AppKit
import Observation

struct UsageWindow: Identifiable, Equatable {
    var id: String
    var name: String
    var used: Double
    var resetsAt: Date?
    var resetDescription: String? = nil
    var remaining: Double { max(0, 100 - used) }
    var expired: Bool { resetsAt.map { $0 <= Date() } ?? false }
}

struct ProviderUsage {
    var windows: [UsageWindow] = []
    var updatedAt: Date?
    var message: String
}

enum UsageParser {
    static func codex(_ data: Data) throws -> [UsageWindow] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ToolError.message("Codex returned an unreadable response.")
        }
        if let error = root["error"] as? [String: Any] { throw ToolError.message(error["message"] as? String ?? "Codex could not read account limits.") }
        let result = root["result"] as? [String: Any] ?? root
        let byID = result["rateLimitsByLimitId"] as? [String: Any]
        let limits = byID?["codex"] as? [String: Any] ?? result["rateLimits"] as? [String: Any] ?? [:]
        return ["primary", "secondary"].compactMap { key in
            guard let window = limits[key] as? [String: Any], let used = window["usedPercent"] as? Double,
                  used.isFinite, (0...100).contains(used) else { return nil }
            let minutes = window["windowDurationMins"] as? Int
            let label = minutes.map { $0 % 1440 == 0 ? "\($0 / 1440)-day allowance" : $0 % 60 == 0 ? "\($0 / 60)-hour allowance" : "\($0)-minute allowance" } ?? key.capitalized
            return UsageWindow(id: key, name: label, used: used, resetsAt: (window["resetsAt"] as? Double).map(Date.init(timeIntervalSince1970:)))
        }
    }
    static func claude(_ data: Data) throws -> [UsageWindow] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ToolError.message("Unreadable Claude usage update.") }
        let limits = root["rate_limits"] as? [String: Any] ?? [:]
        return [("five_hour", "5-hour allowance"), ("seven_day", "7-day allowance"), ("spend_limit", "Spend allowance")].compactMap { key, name in
            guard let window = limits[key] as? [String: Any], let used = window["used_percentage"] as? Double,
                  used.isFinite, used >= 0, used <= 100 || key == "spend_limit" else { return nil }
            return UsageWindow(id: key, name: name, used: used, resetsAt: (window["resets_at"] as? Double).map(Date.init(timeIntervalSince1970:)))
        }
    }
}

enum CodexUsageClient {
    static func executable() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let paths = [home.appendingPathComponent(".local/bin/codex").path, "/opt/homebrew/bin/codex", "/usr/local/bin/codex", "/Applications/Codex.app/Contents/Resources/codex"]
        return paths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }).map { URL(fileURLWithPath: $0) }
    }
    static func read(executable: URL, timeoutSeconds: Double = 20) async throws -> Data {
        let process = Process()
        process.executableURL = executable
        process.arguments = ["app-server", "--listen", "stdio://"]
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "\(FileManager.default.homeDirectoryForCurrentUser.path)/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        process.environment = environment
        let input = Pipe(); let output = Pipe()
        process.standardInput = input; process.standardOutput = output; process.standardError = FileHandle.nullDevice
        try process.run()
        let timeout = Task {
            do { try await Task.sleep(for: .seconds(timeoutSeconds)) } catch { return }
            if process.isRunning { process.terminate() }
        }
        defer {
            timeout.cancel()
            try? input.fileHandleForWriting.close()
            if process.isRunning { process.terminate() }
        }
        func send(_ object: [String: Any]) throws {
            var data = try JSONSerialization.data(withJSONObject: object)
            data.append(10)
            try input.fileHandleForWriting.write(contentsOf: data)
        }
        try send(["id": 1, "method": "initialize", "params": ["clientInfo": ["name": "socius", "version": "0.1.0"]]])
        for try await line in output.fileHandleForReading.bytes.lines {
            try Task.checkCancellation()
            guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { continue }
            if object["id"] as? Int == 1 {
                if object["error"] != nil { throw ToolError.message("Could not initialize Codex. Update the Codex CLI and retry.") }
                try send(["method": "initialized"])
                try send(["id": 2, "method": "account/rateLimits/read"])
            } else if object["id"] as? Int == 2 { return Data(line.utf8) }
        }
        throw ToolError.message("Codex closed the connection without returning limits. Check your CLI sign-in and try again.")
    }
}

@Observable final class UsageService {
    var codex = ProviderUsage(message: "")
    var claude = ProviderUsage(message: "")
    private(set) var codexLoading = false
    private(set) var claudeLoading = false
    var busy: Bool { codexLoading || claudeLoading }
    private var claudeExecutable: URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [home + "/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }.map { URL(fileURLWithPath: $0) }
    }
    var claudeCLIAvailable: Bool { claudeExecutable != nil }
    var codexCLIAvailable: Bool { CodexUsageClient.executable() != nil }
    func loadInstalledCLIs() async {
        async let codexRead: Void = loadCodex(force: false)
        async let claudeRead: Void = loadClaudeCLI(force: false)
        _ = await (codexRead, claudeRead)
    }
    func loadClaudeCLI(force: Bool = true) async {
        if !force, !claude.windows.isEmpty, let updated = claude.updatedAt, Date().timeIntervalSince(updated) < 60 { return }
        guard !Task.isCancelled, let executable = claudeExecutable, !claudeLoading else { return }
        claudeLoading = true
        defer { claudeLoading = false }
        if claude.windows.isEmpty { claude.message = "Reading Claude CLI /usage…" }
        do {
            let windows = try await ClaudeCLIUsage.read(executable: executable,
                directory: directory.appendingPathComponent("UsageCLI"))
            claude = ProviderUsage(windows: windows.map {
                UsageWindow(id: $0.name, name: $0.name, used: $0.used, resetsAt: nil, resetDescription: $0.reset)
            }, updatedAt: Date(), message: "From Claude CLI /usage · account limits across models")
        } catch is CancellationError {
            claude.message = "Refresh interrupted. Reopen AI Credits to retry."
        } catch {
            claude.message = error.localizedDescription
        }
    }
    func authorizeClaude() async {
        guard !claudeLoading else { return }
        claudeLoading = true
        defer { claudeLoading = false }
        do {
            let data = try await ClaudeAccountUsage.read(allowAuthorization: true)
            let windows = try UsageParser.claudeAccount(data)
            guard !windows.isEmpty else { throw ToolError.message("Claude did not return allowances.") }
            claude = ProviderUsage(windows: windows, updatedAt: Date(), message: "One-time account sync · token not retained")
        } catch { claude.message = error.localizedDescription }
    }
    let directory: URL
    init(directory: URL) {
        self.directory = directory
    }
    func loadCodex(force: Bool = true) async {
        if !force, !codex.windows.isEmpty, let updated = codex.updatedAt, Date().timeIntervalSince(updated) < 60 { return }
        guard !codexLoading else { return }
        codexLoading = true; defer { codexLoading = false }
        guard let executable = CodexUsageClient.executable() else {
            codex.message = "Codex CLI not found. Install it and sign in with your ChatGPT account."; return
        }
        do {
            let data = try await CodexUsageClient.read(executable: executable)
            codex.windows = try UsageParser.codex(data)
            codex.updatedAt = Date()
            codex.message = codex.windows.isEmpty ? "No subscription limits returned for this account." : "From your signed-in Codex account"
        } catch { codex.message = error.localizedDescription }
    }

}

enum ClaudeUsageBridge {
    static func shellQuote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    static func install(directory: URL, settingsURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json"), executable: URL? = Bundle.main.executableURL) throws {
        var settings: [String: Any] = [:]
        let exists = FileManager.default.fileExists(atPath: settingsURL.path)
        let original = exists ? try Data(contentsOf: settingsURL) : Data("{}".utf8)
        guard let decoded = try JSONSerialization.jsonObject(with: original) as? [String: Any] else { throw ToolError.message("Claude settings are unreadable. No changes were made.") }
        settings = decoded
        var status = settings["statusLine"] as? [String: Any] ?? ["type": "command"]
        let existing = status["command"] as? String
        if existing?.contains("--claude-statusline") == true {
            guard FileManager.default.fileExists(atPath: directory.appendingPathComponent("claude-bridge.json").path) else {
                throw ToolError.message("A Socius status-line command already exists, but its backup is missing. Review Claude settings before reconnecting.")
            }
            return
        }
        guard let executable else { throw ToolError.message("Could not locate Socius. Launch the app bundle and retry.") }
        let backup = directory.appendingPathComponent("claude-settings-before-bridge-\(UUID().uuidString).json")
        try original.write(to: backup, options: .atomic)
        var command = shellQuote(executable.path) + " --claude-statusline"
        if let existing, !existing.isEmpty { command += " --forward " + shellQuote(existing) }
        status["type"] = "command"; status["command"] = command
        settings["statusLine"] = status
        let state: [String: Any] = ["previousStatusLine": decoded["statusLine"] ?? NSNull(), "installedCommand": command, "settingsPath": settingsURL.path]
        try JSONSerialization.data(withJSONObject: state).write(to: directory.appendingPathComponent("claude-bridge.json"), options: .atomic)
        try FileManager.default.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys]).write(to: settingsURL, options: .atomic)
    }
    static func uninstall(directory: URL) throws {
        let stateURL = directory.appendingPathComponent("claude-bridge.json")
        guard let state = try JSONSerialization.jsonObject(with: Data(contentsOf: stateURL)) as? [String: Any],
              let path = state["settingsPath"] as? String, let installed = state["installedCommand"] as? String else {
            throw ToolError.message("The Claude bridge backup could not be read. Your settings were left unchanged.")
        }
        let settingsURL = URL(fileURLWithPath: path)
        guard var settings = try JSONSerialization.jsonObject(with: Data(contentsOf: settingsURL)) as? [String: Any],
              (settings["statusLine"] as? [String: Any])?["command"] as? String == installed else {
            throw ToolError.message("Your status line has changed since connecting. No settings were overwritten; remove the Socius command manually if needed.")
        }
        if state["previousStatusLine"] is NSNull { settings.removeValue(forKey: "statusLine") }
        else { settings["statusLine"] = state["previousStatusLine"] }
        try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys]).write(to: settingsURL, options: .atomic)
        try FileManager.default.removeItem(at: stateURL)
        try? FileManager.default.removeItem(at: directory.appendingPathComponent("claude-usage.json"))
    }
    /// CLI mode receives a documented status-line payload; retain only limits, never conversation data.
    static func receive() {
        let input = FileHandle.standardInput.readDataToEndOfFile()
        if input.count <= 1_000_000, let object = try? JSONSerialization.jsonObject(with: input) as? [String: Any] {
            let directory = SociusStorage.directory
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let reduced: [String: Any] = ["rate_limits": object["rate_limits"] as? [String: Any] ?? [:]]
                try JSONSerialization.data(withJSONObject: reduced).write(to: directory.appendingPathComponent("claude-usage.json"), options: .atomic)
            } catch { /* Never break the user's status line if the cache is unavailable. */ }
        }
        if let flag = CommandLine.arguments.firstIndex(of: "--forward"), CommandLine.arguments.indices.contains(flag + 1) {
            let process = Process(); let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", CommandLine.arguments[flag + 1]]
            process.standardInput = pipe
            do {
                try process.run()
                try pipe.fileHandleForWriting.write(contentsOf: input)
                try pipe.fileHandleForWriting.close()
                process.waitUntilExit()
            } catch { }
        } else { print("Mochi is keeping an eye on your usage.") }
    }
}
