import Foundation
import Testing
@testable import Socius

@MainActor @Suite struct PlaygroundTests {
    @Test func activityKeepsPreviewEngagedThenReturnsToIdle() {
        let preview = PlaygroundPresence()
        preview.simulateIdle()
        preview.tick(held: true)
        #expect(preview.phase == .engaged)
        preview.tick(held: false)
        #expect(preview.phase == .tucked)
    }

    @Test func previewTimingsAndRemindersAreIndependent() {
        let first = PlaygroundPresence()
        let second = PlaygroundPresence()
        first.idleSeconds = 1
        first.tick(held: false, now: Date().addingTimeInterval(2))
        #expect(first.phase == .tucked)
        first.simulateReminder()
        #expect(first.phase == .peeking)
        #expect(second.phase == .engaged)
        #expect(second.idleSeconds == 30)
    }
}
