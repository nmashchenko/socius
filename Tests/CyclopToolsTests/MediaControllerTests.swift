import Testing
@testable import CyclopTools

@MainActor @Suite(.serialized) struct MediaControllerTests {
    private var spotify: PlayerState {
        PlayerState(app: .spotify, isPlaying: true, title: "Spotify track", artist: "Artist", album: "Album",
                    duration: 240, position: 30, artworkURL: nil)
    }

    @Test func anotherAppsPausedSessionDoesNotHideSpotify() {
        let state = spotify
        let media = MediaController(readSpotify: { $0(.success(state)) })
        media.setActive(true)
        defer { media.stop() }
        media.apply(NowPlayingFeed.Snapshot(title: "Paused browser video", source: "Arc"))
        #expect(media.track?.title == state.title)
        #expect(media.isPlaying)
        #expect(media.sourceName == "Spotify")
        media.apply(NowPlayingFeed.Snapshot())
        #expect(media.track?.title == state.title)
    }

    @Test func deniedAutomationIsShownAsAnAccessError() {
        let media = MediaController(readSpotify: { $0(.failure(.scripting(-1743))) })
        media.setActive(true)
        defer { media.stop() }
        media.apply(NowPlayingFeed.Snapshot(source: "Arc"))
        #expect(media.track == nil)
        #expect(media.readError?.contains("Automation") == true)
    }

    @Test func closingMusicRejectsALateSpotifyRead() throws {
        var completion: ((Result<PlayerState?, PlayerBridge.ReadError>) -> Void)?
        let media = MediaController(readSpotify: { completion = $0 })
        media.setActive(true)
        defer { media.stop() }
        media.apply(NowPlayingFeed.Snapshot(source: "Arc"))
        let reply = try #require(completion)
        media.setActive(false)
        reply(.success(spotify))
        #expect(media.track == nil)
    }

    @Test func freshSpotifyFeedWinsOverAnOlderScriptRead() throws {
        var completion: ((Result<PlayerState?, PlayerBridge.ReadError>) -> Void)?
        let media = MediaController(readSpotify: { completion = $0 })
        media.setActive(true)
        defer { media.stop() }
        media.apply(NowPlayingFeed.Snapshot(source: "Arc"))
        let reply = try #require(completion)
        media.apply(NowPlayingFeed.Snapshot(isPlaying: true, title: "Newer track", duration: 200, source: "Spotify"))
        reply(.success(spotify))
        #expect(media.track?.title == "Newer track")
    }
}
