import AppKit
import Observation

/// AppleScript execution is blocking; isolate it from the animation/UI actor.
nonisolated enum SpotifyScript {
    @concurrent static func run(_ body: String) async throws -> [String] {
        guard let script = NSAppleScript(source: "with timeout of 8 seconds\ntell application id \"com.spotify.client\"\n\(body)\nend tell\nend timeout") else {
            throw NSError(domain: "Spotify", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not prepare Spotify controls."])
        }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            let code = error[NSAppleScript.errorNumber] as? Int ?? 1
            let message = code == -1743 ? "Allow Socius to control Spotify in System Settings → Privacy & Security → Automation." : error[NSAppleScript.errorMessage] as? String ?? "Spotify did not respond."
            throw NSError(domain: "Spotify", code: code, userInfo: [NSLocalizedDescriptionKey: message])
        }
        guard result.numberOfItems > 0 else { return [] }
        return (1...result.numberOfItems).map { result.atIndex($0)?.stringValue ?? "" }
    }
}

@Observable final class SpotifyService {
    var connected = false
    private(set) var busy = false
    private(set) var title = "Your soundtrack"
    private(set) var artist = "Connect the Spotify app on this Mac."
    private(set) var playing = false
    private(set) var hasTrack = false
    private(set) var artwork: URL?
    var error: String?
    enum Action: String { case previous = "previous track", toggle = "playpause", next = "next track" }

    func connect() async {
        guard !busy else { return }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client") else {
            error = "Install the Spotify desktop app to use Music."; return
        }
        do {
            let config = NSWorkspace.OpenConfiguration(); config.activates = false
            _ = try await NSWorkspace.shared.openApplication(at: url, configuration: config)
            connected = true
            await refresh()
        } catch { self.error = error.localizedDescription }
    }
    func refresh() async {
        guard connected, !busy else { return }
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").isEmpty else {
            hasTrack = false; playing = false; title = "Spotify is closed"; artist = "Open Spotify to keep listening."; return
        }
        busy = true; defer { busy = false }
        do {
            let parts = try await SpotifyScript.run("return {name of current track, artist of current track, player state as string, artwork url of current track}")
            guard parts.count == 4 else { throw ToolError.message("Play a song in Spotify to see it here.") }
            title = parts[0]; artist = parts[1]; playing = parts[2] == "playing"
            artwork = URL(string: parts[3]); hasTrack = true; error = nil
        } catch { self.error = error.localizedDescription; hasTrack = false }
    }
    func control(_ action: Action) async {
        guard connected, !busy else { return }
        busy = true
        do {
            _ = try await SpotifyScript.run(action.rawValue)
            busy = false; await refresh()
        } catch { busy = false; self.error = error.localizedDescription }
    }
    func open() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client") {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        } else { error = "Install the Spotify desktop app to use Music." }
    }
}
