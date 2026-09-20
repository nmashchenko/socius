import AppKit
import Testing
@testable import Socius

@MainActor struct PetAppearanceTests {
    @Test func pettingGivesSmallCareAndCapsAtFullHappiness() {
        let pet = PetModel()
        pet.happiness = 40
        pet.pet()
        #expect(pet.happiness == 42)
        pet.happiness = 99
        pet.pet()
        #expect(pet.happiness == 100)
    }
    @Test func displayScaleUsesLogicalDimensionsAndHonorsAdjustment() {
        #expect(PetMetrics.scale(for: CGSize(width: 1440, height: 900), adjustment: 1) == 1)
        #expect(PetMetrics.scale(for: CGSize(width: 2560, height: 1440), adjustment: 1) == 1.2)
        #expect(PetMetrics.scale(for: CGSize(width: 1440, height: 900), adjustment: 1.4) == 1.4)
        #expect(PetMetrics.scale(for: CGSize(width: 1440, height: 900), adjustment: .nan) == 1)
    }
    @Test func topBoundaryUsesVisibleHeadRatherThanEmptySpeechMargin() {
        let metrics = PetMetrics(scale: 1.2)
        let screen = CGRect(x: -1920, y: 40, width: 1920, height: 1000)
        let frame = metrics.frame(around: CGPoint(x: screen.midX, y: screen.maxY), in: screen)
        #expect(abs(frame.minY + metrics.headFromBottom - (screen.maxY - 4)) < 0.01)
        #expect(frame.maxY > screen.maxY)
    }
    @Test func bottomBoundaryAllowsTransparentFooterBelowWorkArea() {
        let screen = CGRect(x: -1920, y: 60, width: 1920, height: 1000)
        for scale in [0.75, 1.0, 1.4] {
            let metrics = PetMetrics(scale: scale)
            let frame = metrics.frame(around: CGPoint(x: screen.midX, y: screen.minY), in: screen)
            #expect(abs(frame.minY + metrics.feetFromBottom - screen.minY) < 0.01)
            #expect(frame.minY < screen.minY)
        }
    }
    @Test func automaticSizingKeepsPetCenterAndSummonFinishesAtCursor() throws {
        _ = NSApplication.shared
        let screen = try #require(NSScreen.main)
        let pet = PetModel()
        let panel = PetPanel(contentRect: CGRect(x: screen.visibleFrame.midX, y: screen.visibleFrame.minY + 100, width: 240, height: 270), styleMask: .borderless, backing: .buffered, defer: false)
        let center = CGPoint(x: panel.frame.midX, y: panel.frame.minY + 120)
        let dock = EdgeDockController(model: pet, automaticSizing: true, reduceMotion: { true })
        dock.start(window: panel)
        defer { dock.stop(); panel.orderOut(nil) }
        #expect(abs(panel.frame.midX - center.x) < 1)
        #expect(abs(panel.frame.minY + pet.metrics.centerFromBottom - center.y) < 1)
        let destination = CGPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.midY)
        dock.summon(at: destination, on: screen)
        #expect(dock.phase == .engaged)
        #expect(abs(panel.frame.midX - destination.x) < 1)
        #expect(abs(panel.frame.minY + pet.metrics.centerFromBottom - destination.y) < 1)
    }
    @Test func returningToTopKeepsTheVisiblePetNearMenuBar() throws {
        _ = NSApplication.shared
        let screen = try #require(NSScreen.main)
        let pet = PetModel()
        let home = pet.metrics.frame(around: CGPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.maxY), in: screen.visibleFrame)
        let panel = PetPanel(contentRect: home, styleMask: .borderless, backing: .buffered, defer: false)
        let input = PetPointerRegion()
        panel.contentView = input
        panel.setFrame(home, display: false)
        let dock = EdgeDockController(model: pet, reduceMotion: { true })
        dock.start(window: panel)
        defer { dock.stop(); panel.orderOut(nil) }
        dock.beginIdle()
        dock.interact()
        #expect(abs(panel.frame.minY - home.minY) < 1)
        #expect(panel.frame.maxY > screen.visibleFrame.maxY)
    }
    @Test func draggingCanPlaceFeetAtBottomOfWorkArea() throws {
        _ = NSApplication.shared
        let screen = try #require(NSScreen.main)
        let pet = PetModel()
        let home = pet.metrics.frame(around: CGPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.midY), in: screen.visibleFrame)
        let panel = PetPanel(contentRect: home, styleMask: .borderless, backing: .buffered, defer: false)
        let input = PetPointerRegion()
        panel.contentView = input
        let dock = EdgeDockController(model: pet, reduceMotion: { true })
        dock.start(window: panel)
        defer { dock.stop(); panel.orderOut(nil) }
        let pointer = CGPoint(x: home.midX, y: home.minY + pet.metrics.centerFromBottom)
        dock.beginUserDrag(at: pointer)
        dock.dragPet(to: CGPoint(x: pointer.x, y: screen.visibleFrame.minY + pet.metrics.size / 2))
        dock.endUserDrag()
        #expect(abs(panel.frame.minY + pet.metrics.feetFromBottom - screen.visibleFrame.minY) <= 1)
    }

}
