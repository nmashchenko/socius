import AppKit
import Testing
@testable import Socius

@MainActor struct WelcomeWindowSessionTests {
    @Test func closingEarlyCancelsExactlyOnceAndDoesNotCountAsCompletion() {
        _ = NSApplication.shared
        let panel = PetPanel(contentRect: CGRect(x: 100, y: 100, width: 200, height: 200), styleMask: [.borderless, .closable], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        var results: [Bool] = []
        let session = WelcomeWindowSession(window: panel) { results.append($0) }
        #expect(!panel.hidesOnDeactivate)
        #expect(panel.collectionBehavior.contains(.canJoinAllSpaces))
        panel.orderFrontRegardless()
        panel.close()
        #expect(results == [false])
        // A delayed completion from the old SwiftUI animation cannot finish
        // a replacement introduction or mark a cancelled one as complete.
        session.complete()
        #expect(results == [false])
    }
    @Test func intentionalCompletionIsNotOverwrittenByWindowCleanup() {
        _ = NSApplication.shared
        let panel = PetPanel(contentRect: CGRect(x: 100, y: 100, width: 200, height: 200), styleMask: .borderless, backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        var results: [Bool] = []
        let session = WelcomeWindowSession(window: panel) { results.append($0) }
        session.complete()
        panel.close()
        session.complete()
        #expect(results == [true])
    }
    @Test func hidingOrEscapingCancelsWithoutWaitingForTheAnimation() {
        _ = NSApplication.shared
        let panel = PetPanel(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        var results: [Bool] = []
        let session = WelcomeWindowSession(window: panel) { results.append($0) }
        session.cancel()
        session.complete()
        #expect(results == [false])
        panel.close()
    }

}
