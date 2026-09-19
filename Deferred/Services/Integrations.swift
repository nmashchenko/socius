import AppKit
import Observation

/// Short-lived system tools. Work and pipe reads run away from the UI actor.
nonisolated enum Command {
    @concurrent static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval = 12) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
        let output = Pipe(); process.standardOutput = output; process.standardError = output
        try process.run()
        let watchdog = Task {
            try? await Task.sleep(for: .seconds(timeout))
            if !Task.isCancelled && process.isRunning { process.terminate() }
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit(); watchdog.cancel()
        let result = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard process.terminationStatus == 0 else { throw AppError.message(result.isEmpty ? "The operation timed out or was cancelled." : result) }
        return result
    }
}

@Observable final class SpotifyService {
    var title = "Your soundtrack, one click away."
    var artist = "Connect Spotify on this Mac"
    var playing = false
    var connected = false
    var busy = false
    var error: String?
    var progress: Double = 0
    var duration: Double = 1
    var artwork: URL?
    func connect() async { connected = true; await refresh() }
    func refresh() async {
        guard connected, !busy else { return }
        guard NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").first != nil else {
            title = "Spotify is not running"; artist = "Open Spotify to start listening"; playing = false; return
        }
        busy = true; defer { busy = false }
        do {
            let result = try await Command.run("/usr/bin/osascript", ["-e", """
            tell application "Spotify"
                return (name of current track) & linefeed & (artist of current track) & linefeed & (player state as string) & linefeed & (player position as string) & linefeed & (duration of current track as string) & linefeed & (artwork url of current track)
            end tell
            """])
            let parts = result.components(separatedBy: "\n")
            guard parts.count >= 5 else { throw AppError.message("Play a song in Spotify to see it here.") }
            title = parts[0]; artist = parts[1]; playing = parts[2] == "playing"
            progress = Double(parts[3]) ?? 0; duration = max(1, (Double(parts[4]) ?? 1000) / 1000)
            artwork = parts.count > 5 ? URL(string: parts[5]) : nil; error = nil
        } catch { self.error = error.localizedDescription }
    }
    func control(_ action: Action) async {
        do {
            _ = try await Command.run("/usr/bin/osascript", ["-e", "tell application \"Spotify\" to \(action.rawValue)"])
            await refresh()
        } catch { self.error = error.localizedDescription }
    }
    enum Action: String { case previous = "previous track", toggle = "playpause", next = "next track" }
    func seek(_ seconds: Double) async {
        guard seconds.isFinite else { return }
        do {
            _ = try await Command.run("/usr/bin/osascript", ["-e", "tell application \"Spotify\" to set player position to \(max(0, min(duration, seconds)))"])
            await refresh()
        } catch { self.error = error.localizedDescription }
    }
    func open() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client") {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        } else { error = "Install the Spotify desktop app to connect playback controls." }
    }
}

@Observable final class UsageService {
    var codex = ProviderUsage(message: "Connect your signed-in Codex CLI to see account limits.")
    var claude = ProviderUsage(message: "Set up the Claude status-line bridge to see account limits.")
    var busy = false
    let directory: URL
    init(directory: URL) { self.directory = directory }
    func refresh() async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        readClaude()
        guard let helper = Bundle.main.url(forResource: "codex-usage", withExtension: "py") else {
            codex.message = "Build the app bundle with Scripts/bundle.sh to connect Codex."; return
        }
        do {
            let output = try await Command.run("/usr/bin/python3", [helper.path], timeout: 20)
            codex.windows = try UsageParser.codex(Data(output.utf8)); codex.updatedAt = Date()
            codex.message = codex.windows.isEmpty ? "No account limits returned. Sign in to Codex with your ChatGPT account." : "From your signed-in Codex account"
        } catch { codex.message = error.localizedDescription }
    }
    func readClaude() {
        let file = directory.appendingPathComponent("claude-usage.json")
        do {
            claude.windows = try UsageParser.claude(Data(contentsOf: file))
            claude.updatedAt = try file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            claude.message = claude.windows.isEmpty ? "No limits in the last Claude update. Start a conversation with a supported subscription." : "Updates while you use Claude Code"
        } catch { claude.message = "Waiting for Claude Code. Install the status-line bridge using the setup guide." }
    }
}
