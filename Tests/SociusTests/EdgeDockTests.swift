import Foundation
import AppKit
import SwiftUI
import Testing
@testable import Socius

@MainActor @Suite struct EdgeDockTests {
    @Test func developerTimingOverridesApplyToHideAndPeek() {
        let start = Date(timeIntervalSince1970: 1000)
        var schedule = IdleSchedule(now: start)
        schedule.idleSeconds = 3
        schedule.peekSeconds = 8
        schedule.interact(at: start)
        #expect(!schedule.shouldHide(at: start.addingTimeInterval(2)))
        #expect(schedule.shouldHide(at: start.addingTimeInterval(3)))
        schedule.tucked(at: start)
        #expect(!schedule.shouldPeek(at: start.addingTimeInterval(7)))
        #expect(schedule.shouldPeek(at: start.addingTimeInterval(8)))
    }
    @Test func inactivityResetsWhenPetIsTouched() {
        let start = Date(timeIntervalSince1970: 1000)
        var schedule = IdleSchedule(now: start)
        #expect(!schedule.shouldHide(at: start.addingTimeInterval(9)))
        #expect(schedule.shouldHide(at: start.addingTimeInterval(10)))
        schedule.interact(at: start.addingTimeInterval(8))
        #expect(!schedule.shouldHide(at: start.addingTimeInterval(12)))
        #expect(schedule.shouldHide(at: start.addingTimeInterval(18)))
    }
    @Test func normalReminderWaitsThirtySeconds() {
        let start = Date(timeIntervalSince1970: 1000)
        var schedule = IdleSchedule(now: start)
        schedule.tucked(at: start.addingTimeInterval(10))
        #expect(!schedule.shouldPeek(at: start.addingTimeInterval(39)))
        #expect(schedule.shouldPeek(at: start.addingTimeInterval(40)))
        let reminder0 = schedule.takeReminder(at: start.addingTimeInterval(29))
        #expect(!reminder0)
        let reminder1 = schedule.takeReminder(at: start.addingTimeInterval(30))
        #expect(reminder1)
        let reminder2 = schedule.takeReminder(at: start.addingTimeInterval(45))
        #expect(!reminder2)
        let reminder3 = schedule.takeReminder(at: start.addingTimeInterval(60))
        #expect(reminder3)
        schedule.interact(at: start.addingTimeInterval(61))
        #expect(schedule.nextPeek == nil)
        let reminder4 = schedule.takeReminder(at: start.addingTimeInterval(70))
        #expect(!reminder4)
    }
    @Test(arguments: [CGRect(x: 0, y: 25, width: 1440, height: 875), CGRect(x: -1920, y: -200, width: 1920, height: 1080)])
    func retreatKeepsHeightOnEitherSideAndNegativeOriginDisplays(_ screen: CGRect) {
        for distance in [30.0, screen.width - 300] {
            let home = CGRect(x: screen.minX + distance, y: screen.minY + 210, width: 240, height: 270)
            let dock = EdgeDockGeometry.dockFrame(home: home, visibleScreen: screen)
            #expect(dock.minY == home.minY)
            #expect(dock.size == home.size)
            #expect(dock.minX == screen.minX || dock.maxX == screen.maxX)
            #expect(EdgeDockGeometry.restoredFrame(home: home, visibleScreen: screen) == home)
        }
    }
    @Test func disconnectedScreenRestoresPetToReachablePosition() {
        let screen = CGRect(x: 0, y: 25, width: 1440, height: 875)
        let oldHome = CGRect(x: -1800, y: 1300, width: 240, height: 270)
        let restored = EdgeDockGeometry.restoredFrame(home: oldHome, visibleScreen: screen)
        #expect(screen.contains(restored))
    }
    @Test(arguments: [CGRect(x: 0, y: 25, width: 1440, height: 875), CGRect(x: -1920, y: -200, width: 1920, height: 1080)])
    func tuckingAndUntuckingPreserveTheContinuousVisiblePath(_ screen: CGRect) {
        let size = CGSize(width: 240, height: 270)
        for distance in stride(from: -95.0, through: screen.width - size.width + 95, by: 5) {
            let origin = CGPoint(x: screen.minX + distance, y: screen.minY + 80)
            let placement = EdgeDockGeometry.placement(visualOrigin: origin, windowSize: size, visibleScreen: screen)
            #expect(placement.frame.minX + placement.offset == origin.x)
            #expect(placement.frame.minY == origin.y)
            if origin.x >= screen.minX && origin.x <= screen.maxX - size.width {
                #expect(placement.offset == 0)
            } else {
                #expect(placement.frame.minX == screen.minX || placement.frame.maxX == screen.maxX)
            }
        }
    }
    @Test func nativeWindowRetreatPeekAndHoverReturn() {
        _ = NSApplication.shared
        guard let screen = NSScreen.main else { return }
        let home = CGRect(x: screen.visibleFrame.maxX - 300, y: screen.visibleFrame.minY + 80, width: 240, height: 270)
        let panel = PetPanel(contentRect: home, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        let pet = PetModel()
        let dock = EdgeDockController(model: pet, reduceMotion: { true })
        dock.start(window: panel)
        defer { dock.stop() }
        let now = Date()
        dock.menuOpen = true
        dock.update(at: now.addingTimeInterval(31))
        #expect(dock.phase == .engaged)
        dock.menuOpen = false
        dock.update(at: now.addingTimeInterval(62))
        #expect(dock.phase == .tucked)
        #expect(panel.frame.minY == home.minY)
        #expect(panel.frame.maxX == screen.visibleFrame.maxX)
        #expect(abs(dock.offset) == 95)
        dock.update(at: now.addingTimeInterval(90))
        dock.update(at: now.addingTimeInterval(93))
        #expect(dock.phase == .peeking)
        #expect(abs(dock.offset) == 95)
        #expect(dock.reminder != nil)
        dock.hover(true)
        #expect(dock.phase == .peeking)
        dock.interact()
        #expect(dock.phase == .engaged)
        #expect(dock.offset == 0)
        #expect(dock.tilt == 0)
        #expect(panel.frame == home)
        dock.pocketClosed()
        #expect(dock.phase == .tucked)
        dock.enabled = false
        dock.pocketClosed()
        #expect(dock.phase == .engaged)
    }

    @Test(arguments: ["offer", "eat", "game", "play"])
    func closingPocketKeepsCareInPlace(_ activity: String) {
        _ = NSApplication.shared
        guard let screen = NSScreen.main else { return }
        let home = CGRect(x: screen.visibleFrame.midX, y: screen.visibleFrame.minY + 80, width: 240, height: 270)
        let panel = PetPanel(contentRect: home, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        let pet = PetModel()
        let dock = EdgeDockController(model: pet, reduceMotion: { true })
        dock.start(window: panel)
        defer { dock.stop() }
        switch activity {
        case "offer": pet.offer(.snack)
        case "eat": pet.feed()
        case "game": pet.shellGameActive = true
        default: pet.play()
        }
        dock.pocketClosed()
        dock.update(at: Date().addingTimeInterval(60))
        #expect(dock.phase == .engaged)
        #expect(panel.frame == home)
        pet.offering = nil
        pet.shellGameActive = false
        pet.mood = .content
        dock.update(at: Date())
        #expect(dock.phase == .tucked)
    }

    @Test func startsIdleAndCanReturnToItsHome() {
        _ = NSApplication.shared
        guard let screen = NSScreen.main else { return }
        let home = CGRect(x: screen.visibleFrame.midX, y: screen.visibleFrame.minY + 80, width: 240, height: 270)
        let panel = PetPanel(contentRect: home, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        let pet = PetModel()
        let dock = EdgeDockController(model: pet, reduceMotion: { true })
        dock.start(window: panel)
        defer { dock.stop() }
        dock.beginIdle()
        #expect(dock.phase == .tucked)
        #expect(abs(dock.offset) == 95)
        dock.interact()
        #expect(dock.phase == .engaged)
        #expect(panel.frame == home)
    }

    @Test func draggingCancelsRetreatAndKeepsNewPosition() async throws {
        _ = NSApplication.shared
        guard let screen = NSScreen.main else { return }
        let home = CGRect(x: screen.visibleFrame.midX, y: screen.visibleFrame.minY + 80, width: 240, height: 270)
        let panel = PetPanel(contentRect: home, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        let dock = EdgeDockController(model: PetModel())
        dock.start(window: panel)
        defer { dock.stop() }
        dock.simulateIdle()
        dock.beginUserDrag(at: home.origin)
        let destination = CGPoint(x: home.minX - 100, y: home.minY + 70)
        panel.setFrameOrigin(destination)
        dock.endUserDrag()
        try await Task.sleep(for: .milliseconds(400))
        #expect(dock.phase == .engaged)
        #expect(panel.frame.origin == destination)
    }

    @Test func draggingFromEdgeClearsTiltWithoutJumping() {
        _ = NSApplication.shared
        guard let screen = NSScreen.main else { return }
        let panel = PetPanel(contentRect: CGRect(x: screen.visibleFrame.midX, y: screen.visibleFrame.minY + 100, width: 240, height: 270), styleMask: [.borderless], backing: .buffered, defer: false)
        let dock = EdgeDockController(model: PetModel())
        dock.start(window: panel)
        defer { dock.stop() }
        dock.beginIdle()
        let visibleX = panel.frame.minX + dock.offset
        let pointer = CGPoint(x: visibleX + 100, y: panel.frame.midY)
        dock.beginUserDrag(at: pointer)
        dock.dragPet(to: CGPoint(x: pointer.x - 80, y: pointer.y - 20))
        #expect(dock.offset == 0)
        #expect(dock.tilt == 0)
        #expect(panel.frame.minX == visibleX - 80)
        dock.endUserDrag()
        #expect(dock.phase == .engaged)
        #expect(dock.offset == 0)
        #expect(dock.tilt == 0)
    }

    @Test func desktopHostAcceptsFirstClickWhileInactive() {
        let host = PetHostingView(rootView: SwiftUI.EmptyView())
        #expect(host.acceptsFirstMouse(for: nil))
    }
    @Test func displayLinkedTravelFinishesAndReturnsHome() async throws {
        _ = NSApplication.shared
        guard let screen = NSScreen.main else { return }
        let home = CGRect(x: screen.visibleFrame.maxX - 330, y: screen.visibleFrame.minY + 100, width: 240, height: 270)
        let panel = PetPanel(contentRect: home, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        let pet = PetModel()
        let dock = EdgeDockController(model: pet, reduceMotion: { true })
        dock.start(window: panel)
        defer { dock.stop() }
        dock.simulateIdle()
        try await Task.sleep(for: .milliseconds(800))
        #expect(dock.phase == .tucked)
        #expect(panel.frame.minY == home.minY)
        dock.interact()
        try await Task.sleep(for: .milliseconds(800))
        #expect(dock.phase == .engaged)
        #expect(abs(panel.frame.minX - home.minX) < 1)
    }
}
