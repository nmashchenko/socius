import SwiftUI

struct MediaPane: View {
    @ObservedObject var media: MediaController

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scrubHover = false
    @State private var volumeOpen = false
    /// Set while dragging, so the bar follows the finger instead of the clock.
    @State private var scrubbing: Double?

    /// Artwork and the text column share this height, so their top and bottom
    /// edges line up instead of the column floating past them.
    private let blockHeight: CGFloat = 122

    var body: some View {
        if let track = media.track {
            VStack(spacing: 16) {
                HStack(spacing: 18) {
                    artwork(for: track)
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(spacing: 6) {
                            PlaybackIndicator(playing: media.isPlaying)
                            Text(media.isPlaying ? "NOW PLAYING" : "PAUSED")
                                .font(.system(size: 9, weight: .semibold)).tracking(1.2)
                        }.foregroundStyle(Theme.secondary)
                        Text(track.title)
                            .font(.system(size: 21, weight: .semibold, design: .serif))
                            .foregroundStyle(Theme.ink).lineLimit(2)
                        Text(subtitle(for: track))
                            .font(.system(size: 11.5)).foregroundStyle(Theme.secondary).lineLimit(1)
                        Spacer(minLength: 4)
                        controls
                    }.frame(height: blockHeight, alignment: .leading)
                }
                scrubber

            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            emptyState
        }
    }

    /// The system often repeats the title as the album name; showing
    /// "Artist — Title" twice reads like a bug.
    private func subtitle(for track: MediaController.Track) -> String {
        var parts = [track.artist]
        if !track.album.isEmpty, track.album != track.title { parts.append(track.album) }
        return parts.filter { !$0.isEmpty }.joined(separator: " — ")
    }

    // MARK: - Artwork

    /// Covers arrive at whatever size the source publishes, so squareness is
    /// a question about proportion, not about exact pixels: a 300x301 cover is
    /// square to everyone looking at it.
    private func isSquare(_ image: NSImage) -> Bool {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return true }
        return abs(size.width / size.height - 1) < 0.02
    }

    private func artwork(for track: MediaController.Track) -> some View {
        ZStack {
            if let image = media.artwork {
                // A square cover fills the box, as it always has. Anything of
                // another shape is fitted into it instead: `.fill` crops by the
                // shorter side, and a 16:9 thumbnail — what a video in a
                // browser tab publishes — loses 44 % of its width that way,
                // 22 % off each edge. On a video frame those edges are what
                // says which video it is: a face, a caption, an object (#33).
                Theme.surface
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: isSquare(image) ? .fill : .fit)
                    .transition(.opacity)
            } else {
                SkeletonBox(cornerRadius: 14)
            }
        }
        .frame(width: 118, height: 118)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        // The same shape again, this time for the pointer. `clipShape` hides
        // overflow but does not stop it being touched, and that overhang once
        // reached the tab rail on the left, where four icons stopped answering
        // the pointer (#22). Fitting non-square covers takes the overflow away
        // at its source; this stays as the guard it always was.
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        )
        .shadow(color: Theme.ink.opacity(0.16), radius: 9, y: 4)
        .scaleEffect(media.isPlaying ? 1 : 0.96)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: media.isPlaying)
        .animation(reduceMotion ? nil : Theme.artworkAnimation, value: media.artwork)
    }

    // MARK: - Scrubber

    private var progress: Double {
        if let scrubbing { return scrubbing }
        guard media.duration > 0 else { return 0 }
        return min(max(media.position / media.duration, 0), 1)
    }

    private var scrubber: some View {
        HStack(spacing: 10) {
            Text(formatTime(progress * media.duration))
                .frame(width: 32, alignment: .leading)

            GeometryReader { geo in
                let width = geo.size.width
                let filled = width * progress
                let height: CGFloat = scrubHover ? 6 : 4

                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.surface).frame(height: height)
                    // Deliberately unanimated: a seek has to land under the
                    // cursor at once. Smoothness comes from the tick rate
                    // instead, which keeps each step well under a pixel.
                    Capsule()
                        .fill(Theme.ink.opacity(0.9))
                        .frame(width: filled, height: height)
                    if scrubHover {
                        Circle()
                            .fill(.white)
                            .frame(width: 11, height: 11)
                            .offset(x: min(max(filled - 5.5, 0), width - 11))
                            .shadow(color: .black.opacity(0.4), radius: 3)
                    }
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .onHover { scrubHover = $0 }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard width > 0 else { return }
                            scrubbing = min(max(value.location.x / width, 0), 1)
                        }
                        .onEnded { value in
                            guard width > 0 else { return }
                            let target = min(max(value.location.x / width, 0), 1)
                            // Seek first: clearing `scrubbing` beforehand would
                            // drop the bar back to the old position for a frame
                            // before the new one lands.
                            media.seek(to: media.duration * target)
                            scrubbing = nil
                        }
                )
                .animation(Theme.contentAnimation, value: scrubHover)
            }
            .frame(height: 14)

            Text(formatTime(media.duration))
                .frame(width: 32, alignment: .trailing)
        }
        .font(.system(size: 10, weight: .medium).monospacedDigit())
        .foregroundStyle(Theme.tertiary)
    }

    // MARK: - Transport

    /// Skipping is dimmed, not hidden, when the player does not offer it — a
    /// video in a browser tab has nothing to skip to, so the command would
    /// leave and nothing would happen. Dim says "not here"; a button that
    /// looks live and does nothing says "broken". The system's own Now Playing
    /// widget dims the same two arrows on the same session.
    private var controls: some View {
        HStack(spacing: 12) {
            if volumeOpen {
                VStack(alignment: .leading, spacing: 2) {
                    Text("System volume · \(Int(media.volume * 100))%")
                        .font(.system(size: 10)).foregroundStyle(Theme.secondary)
                    Slider(value: $media.volume, in: 0...1) { editing in
                        if !editing { media.commitVolume() }
                    }.disabled(!media.volumeAvailable).controlSize(.small)
                        .accessibilityLabel("System volume").tint(Theme.ink)
                }.frame(height: 42)
            } else {

            Button { media.previous() } label: { Image(systemName: "backward.fill") }
                .buttonStyle(MusicControlStyle(prominent: false))
                .disabled(!media.canSkip)
                .opacity(media.canSkip ? 1 : 0.35)
            Button { media.togglePlayPause() } label: {
                Image(systemName: media.isPlaying ? "pause.fill" : "play.fill")
            }
            .contentTransition(.symbolEffect(.replace))
            .buttonStyle(MusicControlStyle(prominent: true))
            .accessibilityLabel(media.isPlaying ? "Pause" : "Play")
            Button { media.next() } label: { Image(systemName: "forward.fill") }
                .buttonStyle(MusicControlStyle(prominent: false))
                .disabled(!media.canSkip)
                .opacity(media.canSkip ? 1 : 0.35)
            }
            Spacer(minLength: 0)
            Button { volumeOpen.toggle(); media.refreshVolume() } label: {
                Image(systemName: volumeOpen ? "checkmark" : media.volume == 0 ? "speaker.slash" : "speaker.wave.2")
            }
            .buttonStyle(MusicControlStyle(prominent: false))
            .accessibilityLabel("System volume")
            .help("System volume")

        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: media.canSkip)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "music.note.list")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(Theme.tertiary)
            // Status, not instruction: an empty pane on its own would not say
            // whether nothing is playing or nothing could be read.
            Text(media.spotifyInstalled ? "Play something in Spotify" : "Spotify Desktop required")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.secondary)
            Text(media.spotifyInstalled ? "Open the desktop app to start listening." : "Install the Spotify desktop app to use Music.")
                .font(.system(size: 11)).foregroundStyle(Theme.secondary)
            Text("Browser player integration is coming later.")
                .font(.system(size: 11)).foregroundStyle(Theme.tertiary)
            if media.spotifyInstalled {
                Button("Open Spotify") { media.openSpotify() }.buttonStyle(.bordered)
            } else {
                Link("Get Spotify", destination: URL(string: "https://www.spotify.com/download/mac/")!)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A playback status glyph, not a sampled audio waveform.
private struct PlaybackIndicator: View {
    let playing: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<4) { index in
                Capsule().frame(width: 2, height: 12)
                    .scaleEffect(y: playing && !reduceMotion ? (pulse ? [0.4, 1.0, 0.6, 0.85][index] : [0.9, 0.4, 1.0, 0.3][index]) : 0.35)
            }
        }.frame(width: 14, height: 12).accessibilityHidden(true)
            .onAppear { update() }
            .onChange(of: playing) { update() }
            .onChange(of: reduceMotion) { update() }
    }
    private func update() {
        withAnimation(nil) { pulse = false }
        if playing && !reduceMotion {
            withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}

private struct MusicControlStyle: ButtonStyle {
    var prominent: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: prominent ? 16 : 13, weight: .semibold))
            .foregroundStyle(prominent ? Color(red: 0.98, green: 0.97, blue: 0.93) : Theme.ink)
            .frame(width: prominent ? 42 : 32, height: prominent ? 42 : 32)
            .background(prominent ? Theme.ink : Theme.ink.opacity(configuration.isPressed ? 0.1 : 0.04), in: Circle())
            .contentShape(Circle())
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
