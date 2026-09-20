import AppKit
import Testing
@testable import Socius

@MainActor @Suite struct PlaygroundTests {
    @Test func dashboardUsesDesktopModelAndTimers() throws {
        _ = NSApplication.shared
        let model = PetModel()
        let presence = EdgeDockController(model: model, reduceMotion: { true })
        let window = PetPanel(contentRect: CGRect(x: 500, y: 400, width: 240, height: 270), styleMask: .borderless, backing: .buffered, defer: false)
        presence.start(window: window)
        defer { presence.stop(); window.orderOut(nil) }
        let dashboard = PlaygroundView(model: model, presence: presence)
        dashboard.model.preview(.hungry)
        #expect(model.fullness == 12)
        dashboard.presence.idleSeconds = 5
        dashboard.presence.peekSeconds = 5
        let now = Date()
        presence.update(at: now.addingTimeInterval(4))
        #expect(presence.phase == .engaged)
        presence.update(at: now.addingTimeInterval(5))
        #expect(presence.phase == .tucked)
        presence.update(at: now.addingTimeInterval(10))
        #expect(presence.phase == .peeking)
        dashboard.presence.interact()
        #expect(presence.phase == .engaged)
        dashboard.presence.simulateReminder()
        #expect(presence.phase == .peeking)
        #expect(presence.reminder != nil)
        dashboard.presence.idleSeconds = IdleSchedule.idleDelay
        dashboard.presence.peekSeconds = IdleSchedule.peekDelay
        #expect(presence.idleSeconds == 10)
        #expect(presence.peekSeconds == 30)
    }
}
