import AppKit

/// Spotify playback, using the system feed when Spotify owns Now Playing.
///
/// Primary source is `NowPlayingFeed`, which reaches MediaRemote through a
/// helper hosted by `/usr/bin/perl`. If that route ever closes, the controller
/// reads Spotify directly if another app owns the session or the helper fails.
@MainActor
final class MediaController: ObservableObject {
    struct Track: Equatable {
        var title: String
        var artist: String
        var album: String
        var key: String
    }

    @Published private(set) var spotifyInstalled = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client") != nil
    func openSpotify() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client") {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        }
    }
    @Published private(set) var track: Track?
    @Published private(set) var artwork: NSImage?
    @Published private(set) var isPlaying = false
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var position: TimeInterval = 0
    @Published private(set) var sourceName: String?
    @Published private(set) var readError: String?
    @Published var volume: Double = 0.5
    @Published private(set) var volumeAvailable = false
    var volumeLabel: String { "System volume" }
    init(readSpotify: @escaping (@escaping (Result<PlayerState?, PlayerBridge.ReadError>) -> Void) -> Void = {
        PlayerBridge.stateResult(of: .spotify, completion: $0)
    }) {
        self.readSpotify = readSpotify
        if ProcessInfo.processInfo.arguments.contains("--render-preview") {
            track = Track(title: "Midnight City", artist: "M83", album: "", key: "preview")
            isPlaying = true; duration = 244; position = 87; volumeAvailable = true
            artwork = NSImage(size: NSSize(width: 240, height: 240), flipped: false) { rect in
                NSColor(red: 0.17, green: 0.23, blue: 0.25, alpha: 1).setFill()
                rect.fill()
                for index in (0..<7).reversed() {
                    NSColor(red: 0.6 + Double(index) * 0.04, green: 0.48 + Double(index) * 0.035, blue: 0.36, alpha: 1).setFill()
                    NSBezierPath(ovalIn: rect.insetBy(dx: CGFloat(index * 13 + 20), dy: CGFloat(index * 13 + 20))).fill()
                }
                return true
            }
        }
    }
    func refreshVolume() {
        let source = "output volume of (get volume settings)"
        PlayerBridge.runScript(source) { [weak self] value in
            guard let self else { return }
            volumeAvailable = value != nil
            if let value { volume = min(1, max(0, Double(value.int32Value) / 100)) }
        }
    }
    func commitVolume() {
        let amount = Int((min(1, max(0, volume)) * 100).rounded())
        let source = "set volume output volume \(amount)"
        PlayerBridge.runScript(source) { [weak self] value in
            if value == nil { self?.refreshVolume() }
        }
    }
    /// Use Spotify's reported capabilities when available.
    @Published private(set) var canSkip = true

    private let feed = NowPlayingFeed()
    private var feedAvailable = true
    private var usingSpotifyScript = false
    private let readSpotify: (@escaping (Result<PlayerState?, PlayerBridge.ReadError>) -> Void) -> Void
    private var stateRequest: UUID?

    private var artworkKey: String?
    private var anchor: (position: TimeInterval, at: Date)?
    /// Where we asked the player to jump, and when — see `apply`.
    private var pendingSeek: (target: TimeInterval, at: Date)?
    private var ticker: Timer?
    private var observers: [Any] = []
    /// Whether the panel is open — the ticker below runs only then.
    private var isActive = false
    private var started = false

    // MARK: - Lifecycle

    func start() {
        guard spotifyInstalled, !started else { return }
        started = true
        feedAvailable = true
        feed.onUpdate = { [weak self] snapshot in self?.apply(snapshot) }
        feed.onUnavailable = { [weak self] in self?.switchToScriptingFallback() }
        feed.start()
        let center = DistributedNotificationCenter.default()
        observers.append(center.addObserver(forName: PlayerApp.spotify.changeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isActive else { return }
                self.refreshFromPlayers()
            }
        })
    }

    func stop() {
        started = false
        isActive = false
        stateRequest = nil
        feed.stop()
        observers.forEach { DistributedNotificationCenter.default().removeObserver($0) }
        observers.removeAll()
        ticker?.invalidate()
        ticker = nil
    }

    /// Panel visibility. The position ticker hangs off this: it exists to move
    /// a bar, and a bar in a collapsed panel is painted for nobody — at four
    /// wake-ups a second for as long as anything plays. The position itself is
    /// never lost, because the anchor records where it stood and when: opening
    /// computes it from there instantly, and the feed's fresh answer corrects
    /// whatever drifted a beat later.
    func setActive(_ active: Bool) {
        isActive = active
        if !active { stateRequest = nil }
        updateTicker()
        guard active else { return }
        let installed = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client") != nil
        spotifyInstalled = installed
        guard installed else { clear(); return }
        start()
        refreshVolume()
        tick()
        if feedAvailable {
            feed.refresh()
        }
        if !feedAvailable || usingSpotifyScript {
            refreshFromPlayers()
        }
    }

    func retrySpotify() {
        guard isActive else { return }
        readError = nil
        refreshFromPlayers()
    }

    // MARK: - Transport

    func togglePlayPause() {
        // Optimistic flip so the button feels instant; the feed corrects it.
        isPlaying.toggle()
        setAnchor(position)
        // Explicitly target Spotify even if another app now owns Now Playing.
        PlayerBridge.playPause(.spotify)
    }

    func next() {
        PlayerBridge.next(.spotify)
    }

    func previous() {
        PlayerBridge.previous(.spotify)
    }

    func seek(to seconds: TimeInterval) {
        guard duration > 0 else { return }
        let clamped = min(max(0, seconds), duration)
        setAnchor(clamped)
        pendingSeek = (clamped, Date())
        // Always address Spotify explicitly. The system player can change
        // between a snapshot and a button press (for example, to an Arc tab).
        PlayerBridge.seek(.spotify, to: clamped)
    }

    // MARK: - Feed

    func apply(_ snapshot: NowPlayingFeed.Snapshot) {
        guard !snapshot.isEmpty, snapshot.source?.lowercased() == "spotify" else {
            usingSpotifyScript = true
            InteractionTrace.record("media system source=otherOrEmpty; query Spotify directly=\(isActive)")
            if isActive { refreshFromPlayers() }
            return
        }
        usingSpotifyScript = false
        stateRequest = nil
        readError = nil
        InteractionTrace.record("media Spotify system snapshot playing=\(snapshot.isPlaying) track=true")

        let key = "\(snapshot.title)|\(snapshot.artist)|\(snapshot.album)"
        track = Track(title: snapshot.title, artist: snapshot.artist, album: snapshot.album, key: key)
        isPlaying = snapshot.isPlaying || snapshot.rate > 0
        duration = snapshot.duration
        let sourceChanged = sourceName != snapshot.source
        sourceName = snapshot.source
        if sourceChanged && isActive { refreshVolume() }
        // Both directions travel together: no player has ever offered one
        // without the other, and two separately dimmed arrows would read as
        // a glitch rather than a limit.
        canSkip = snapshot.offers(.next) && snapshot.offers(.previous)

        let reported = reportedPosition(from: snapshot)

        // A player needs a moment to act on a seek, and until it does it keeps
        // reporting the old position. Accepting that would yank the bar back.
        if let pending = pendingSeek {
            let settled = abs(reported - pending.target) < 2.5
            let expired = Date().timeIntervalSince(pending.at) > 1.5
            if settled || expired {
                pendingSeek = nil
                adopt(reported)
            }
        } else {
            adopt(reported)
        }
        updateTicker()

        if let data = snapshot.artwork {
            artworkKey = key
            decodeArtwork(data, for: key)
        } else if artworkKey != key {
            // Track changed and the payload carried no artwork; the skeleton
            // covers the gap until the system publishes the new cover.
            artworkKey = key
            artwork = nil
        }
    }

    /// JPEG decoding on the main thread is what makes a track change stutter,
    /// so it happens off it and the finished image is handed back.
    private func decodeArtwork(_ data: Data, for key: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let rep = NSBitmapImageRep(data: data), let cgImage = rep.cgImage else { return }
            let image = NSImage(
                cgImage: cgImage,
                size: NSSize(width: rep.pixelsWide, height: rep.pixelsHigh)
            )
            DispatchQueue.main.async { [weak self] in
                guard let self, self.artworkKey == key else { return }
                self.artwork = image
            }
        }
    }

    private func clear() {
        track = nil
        artwork = nil
        artworkKey = nil
        isPlaying = false
        duration = 0
        position = 0
        sourceName = nil
        canSkip = true
        updateTicker()
    }

    // MARK: - Direct Spotify reads

    private func switchToScriptingFallback() {
        guard feedAvailable else { return }
        feedAvailable = false
        usingSpotifyScript = true
        canSkip = true
        NSLog("Socius: Now Playing helper unavailable, falling back to Spotify scripting")

        refreshFromPlayers()
    }

    private func refreshFromPlayers() {
        guard isActive, stateRequest == nil else { return }
        let request = UUID()
        stateRequest = request
        readSpotify { [weak self] result in
            guard let self, self.isActive, self.stateRequest == request else { return }
            self.stateRequest = nil
            let state: PlayerState?
            switch result {
            case .success(let value):
                state = value
                self.readError = nil
                InteractionTrace.record("media direct Spotify track=\(value != nil) playing=\(value?.isPlaying == true)")
            case .failure(let error):
                self.clear()
                self.readError = error.message
                InteractionTrace.record("media direct Spotify failed: \(error)")
                return
            }
            guard let state else { return self.clear() }

            self.canSkip = true
            self.sourceName = state.app.displayName
            self.track = Track(title: state.title, artist: state.artist, album: state.album, key: state.key)
            self.isPlaying = state.isPlaying
            self.duration = state.duration
            self.adopt(state.position)
            self.updateTicker()

            guard self.artworkKey != state.key else { return }
            self.artworkKey = state.key
            self.artwork = nil
            PlayerBridge.artwork(for: state) { [weak self] image in
                guard let self, self.artworkKey == state.key else { return }
                self.artwork = image
            }
        }
    }

    // MARK: - Position

    /// What a report actually says by the time it is read.
    ///
    /// MediaRemote does not keep the elapsed time running. The field is a
    /// reading taken when the session last changed state, and the timestamp
    /// beside it says when — a tab playing for three minutes keeps reporting
    /// the second it started at, and many browsers report a plain zero. Taken
    /// literally, every refresh describes the beginning of the track, and
    /// `adopt` reads the gap as a seek made in the player and obeys it. Which
    /// is exactly what hovering did: open the panel, refresh, bar to zero.
    ///
    /// So the reading is aged by the clock that came with it. A paused session
    /// is left alone — its reading is not moving and there is nothing to add.
    private func reportedPosition(from snapshot: NowPlayingFeed.Snapshot) -> TimeInterval {
        guard snapshot.isPlaying || snapshot.rate > 0, let takenAt = snapshot.takenAt else {
            return snapshot.elapsed
        }
        let since = Date().timeIntervalSince(takenAt)
        // A stamp from the future is not a clock to add to. Trust the reading.
        guard since >= 0 else { return snapshot.elapsed }
        let rate = snapshot.rate > 0 ? snapshot.rate : 1
        let aged = snapshot.elapsed + since * rate
        return snapshot.duration > 0 ? min(aged, snapshot.duration) : aged
    }

    private func setAnchor(_ value: TimeInterval) {
        position = value
        anchor = (value, Date())
    }

    /// Below this a forward correction is pipeline jitter, not movement.
    private let forwardTolerance: TimeInterval = 0.75
    /// A disagreement this large is an event — a seek made in the player
    /// itself, or a track change — not a discrepancy to be smoothed over.
    private let seekThreshold: TimeInterval = 2

    /// Takes a position reported by the player, without letting the report undo
    /// what has already been shown.
    ///
    /// Every reading arrives late: the helper, the pipe and the parse sit
    /// between the player's clock and ours, so a report is normally a little
    /// *behind* the bar. Accepting it moves the bar backwards — and backwards
    /// is the one direction anybody notices, because time does not do it. So
    /// the two directions get different rules rather than one shared tolerance:
    /// backwards only for something big enough to be a real event, forwards for
    /// anything past the jitter. Left alone, the bar keeps its own count, which
    /// runs at exactly the speed the music does.
    private func adopt(_ reported: TimeInterval) {
        var value = max(0, reported)
        if duration > 0 { value = min(value, duration) }
        let delta = value - position

        if delta >= forwardTolerance || delta <= -seekThreshold {
            position = value
            anchor = (value, Date())
        } else {
            // Keep what is on screen and re-base the clock under it, so the
            // ignored difference cannot accumulate into the next comparison.
            anchor = (position, Date())
        }
    }

    private func updateTicker() {
        ticker?.invalidate()
        ticker = nil
        guard isPlaying, isActive else { return }
        // Four times a second: the bar advances in sub-pixel steps, so it reads
        // as smooth without any animation smoothing the seek away with it.
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 0.05
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func tick() {
        guard let anchor, isPlaying else { return }
        let value = anchor.position + Date().timeIntervalSince(anchor.at)
        position = duration > 0 ? min(value, duration) : value
    }
}
