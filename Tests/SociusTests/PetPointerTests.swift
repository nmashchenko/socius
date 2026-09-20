import AppKit
import SwiftUI
import Testing
@testable import Socius

/// Exercise the actual desktop host and NSPanel event dispatch, not just controller methods.
@MainActor @Suite(.serialized) struct PetPointerTests {
    @MainActor private final class Desktop {
        let pet = PetModel()
        let dock: EdgeDockController
        let panel: PetPanel
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let hub: ToolHub

        init(left: Bool = false) throws {
            _ = NSApplication.shared
            let screen = try #require(NSScreen.main)
            let home = CGRect(x: left ? screen.visibleFrame.minX + 300 : screen.visibleFrame.maxX - 540,
                              y: screen.visibleFrame.minY + 150, width: 240, height: 270)
            panel = PetPanel(contentRect: home, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
            panel.isMovableByWindowBackground = false
            panel.isReleasedWhenClosed = false
            dock = EdgeDockController(model: pet)
            hub = ToolHub(store: ToolStore(directory: directory))
            panel.contentView = PetHostingView(rootView: DesktopPetView(model: pet, presence: dock, hub: hub))
            dock.start(window: panel)
            panel.orderFrontRegardless()
            panel.contentView?.layoutSubtreeIfNeeded()
        }

        func close() {
            dock.stop()
            panel.petInput?.cancel()
            panel.orderOut(nil)
            panel.contentView = nil
            hub.store.stop()
            try? FileManager.default.removeItem(at: directory)
        }

        func petPoint() throws -> CGPoint {
            // Choose the middle of the visible part, including when the pet is tucked/clipped.
            let region = try #require(panel.petInput)
            let rect = region.convert(region.bounds.intersection(region.visibleRect), to: nil)
            return panel.convertPoint(toScreen: CGPoint(x: rect.midX, y: rect.midY))
        }

        func send(_ type: NSEvent.EventType, at point: CGPoint) throws {
            let event = try #require(NSEvent.mouseEvent(with: type, location: panel.convertPoint(fromScreen: point),
                modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber,
                context: nil, eventNumber: 1, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1))
            NSApp.sendEvent(event)
        }

        func settle() async throws {
            try await Task.sleep(for: .milliseconds(950))
            panel.contentView?.layoutSubtreeIfNeeded()
        }
    }

    @Test func fullDesktopHostReachesDisplayBottomAndKeepsItAfterIdle() async throws {
        let desktop = try Desktop()
        defer { desktop.close() }
        for screen in NSScreen.screens {
            let home = desktop.pet.metrics.frame(around: CGPoint(x: screen.frame.midX, y: screen.frame.midY), in: screen.petMovementFrame)
            desktop.dock.repositionHome(home)
            try await desktop.settle()
            let start = try desktop.petPoint()
            try desktop.send(.leftMouseDown, at: start)
            let end = CGPoint(x: start.x, y: screen.frame.minY + 1)
            try desktop.send(.leftMouseDragged, at: end)
            #expect(abs(desktop.panel.frame.minY + desktop.pet.metrics.feetFromBottom - screen.frame.minY) < 1)
            try desktop.send(.leftMouseUp, at: end)
            let placed = desktop.panel.frame
            try await desktop.settle()
            #expect(desktop.panel.frame == placed)
            desktop.dock.simulateIdle()
            try await desktop.settle()
            desktop.dock.interact()
            try await desktop.settle()
            #expect(desktop.panel.frame == placed)
        }
    }

    @Test func releasedDragReturnsToIdleEvenWithAStaleHover() async throws {
        let desktop = try Desktop()
        defer { desktop.close() }
        try await desktop.settle()
        let start = try desktop.petPoint()
        try desktop.send(.leftMouseDown, at: start)
        let end = CGPoint(x: start.x - 80, y: start.y + 40)
        try desktop.send(.leftMouseDragged, at: end)
        try desktop.send(.leftMouseUp, at: end)
        desktop.dock.hover(true)
        let released = Date()
        desktop.dock.update(at: released.addingTimeInterval(9))
        #expect(desktop.dock.phase == .engaged)
        desktop.dock.update(at: released.addingTimeInterval(10))
        #expect(desktop.dock.phase == .hiding || desktop.dock.phase == .tucked)
        try await desktop.settle()
        #expect(desktop.dock.phase == .tucked)
    }

    @Test func shellRowIsOutsideThePetDragRegion() async throws {
        let desktop = try Desktop()
        defer { desktop.close() }
        desktop.pet.startShellGame(prize: 1)
        try await desktop.settle()
        let region = try #require(desktop.panel.petInput)
        // The shell row is centered 30 points above the panel bottom.
        let point = CGPoint(x: 120, y: 30)
        let event = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: point,
            modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: desktop.panel.windowNumber, context: nil, eventNumber: 1,
            clickCount: 1, pressure: 1))
        #expect(!region.handle(event))
        #expect(!desktop.dock.pointerPressed)
        let host = try #require(desktop.panel.contentView)
        #expect(host.hitTest(host.convert(point, from: nil)) != nil)

    }

    @Test(arguments: [false, true])
    func repeatedScreenSpaceDragsKeepTheGrabPointAndNewHome(left: Bool) async throws {
        let desktop = try Desktop(left: left)
        defer { desktop.close() }
        try await desktop.settle()
        _ = try #require(desktop.panel.petInput)
        desktop.dock.beginIdle()
        try await desktop.settle()

        for _ in 0..<2 {
            let start = try desktop.petPoint()
            let visibleOrigin = CGPoint(x: desktop.panel.frame.minX + desktop.dock.offset, y: desktop.panel.frame.minY)
            try desktop.send(.leftMouseDown, at: start)
            #expect(desktop.dock.pointerPressed)
            let direction: CGFloat = left ? 1 : -1
            for distance in [8.0, 45, 90, 70, 140] {
                let point = CGPoint(x: start.x + direction * distance, y: start.y + distance / 4)
                try desktop.send(.leftMouseDragged, at: point)
                #expect(abs(desktop.panel.frame.minX - (visibleOrigin.x + point.x - start.x)) < 1)
                #expect(abs(desktop.panel.frame.minY - (visibleOrigin.y + point.y - start.y)) < 1)
                #expect(desktop.dock.offset == 0)
                #expect(desktop.dock.tilt == 0)
            }
            // Mouse-up can carry a newer position than the last drag event.
            let end = CGPoint(x: start.x + direction * 150, y: start.y + 40)
            try desktop.send(.leftMouseUp, at: end)
            let home = desktop.panel.frame
            #expect(abs(home.minX - (visibleOrigin.x + direction * 150)) < 1)
            #expect(!desktop.dock.dragging)
            #expect(!desktop.dock.pointerPressed)
            #expect(desktop.pet.reaction == 0) // a drag must never also pet/click
            try await desktop.settle()
            #expect(desktop.dock.phase == .engaged)
            #expect(desktop.panel.frame == home)
            desktop.dock.simulateIdle()
            try await desktop.settle()
            desktop.dock.interact()
            try await desktop.settle()
            #expect(desktop.panel.frame == home)
            #expect(desktop.dock.offset == 0)
            #expect(desktop.dock.tilt == 0)
        }
    }

    @Test func tuckedClickReturnsUprightAndDraggingClosesPocketWithoutRetreat() async throws {
        let desktop = try Desktop()
        defer { desktop.close() }
        try await desktop.settle()
        let home = desktop.panel.frame
        desktop.dock.beginIdle()
        desktop.dock.simulateReminder()
        try await desktop.settle()
        let point = try desktop.petPoint()
        try desktop.send(.leftMouseDown, at: point)
        try desktop.send(.leftMouseUp, at: point)
        try await desktop.settle()
        #expect(desktop.dock.phase == .engaged)
        #expect(desktop.dock.offset == 0)
        #expect(desktop.dock.tilt == 0)
        #expect(desktop.panel.frame == home)
        #expect(desktop.dock.menuOpen)
        #expect(desktop.panel.childWindows?.count == 1)

        let grab = try desktop.petPoint()
        try desktop.send(.leftMouseDown, at: grab)
        let end = CGPoint(x: grab.x - 120, y: grab.y + 30)
        try desktop.send(.leftMouseDragged, at: end)
        try desktop.send(.leftMouseUp, at: end)
        let newHome = desktop.panel.frame
        // Let the previous click's happy reaction, pocket disposal, and idle watcher finish.
        try await Task.sleep(for: .milliseconds(900))
        #expect(desktop.dock.phase == .engaged)
        #expect(desktop.dock.offset == 0)
        #expect(desktop.dock.tilt == 0)
        #expect(desktop.panel.frame == newHome)
        #expect(!desktop.dock.menuOpen)
        #expect(desktop.panel.childWindows?.isEmpty != false)
        #expect(desktop.pet.reaction == 1)
    }

    @Test func pressPausesReturningAndClickResumesIt() async throws {
        let desktop = try Desktop()
        defer { desktop.close() }
        try await desktop.settle()
        let home = desktop.panel.frame
        desktop.dock.beginIdle()
        desktop.dock.interact()
        try await Task.sleep(for: .milliseconds(60))
        let point = try desktop.petPoint()
        try desktop.send(.leftMouseDown, at: point)
        let paused = desktop.panel.frame
        try await desktop.settle()
        #expect(desktop.panel.frame == paused)
        try desktop.send(.leftMouseUp, at: point)
        try await desktop.settle()
        #expect(desktop.dock.phase == .engaged)
        #expect(desktop.panel.frame == home)
        #expect(desktop.dock.offset == 0)
        #expect(desktop.dock.tilt == 0)
    }

    @Test func draggingInterruptsRetreatAndIgnoresLateDragSamples() async throws {
        let desktop = try Desktop()
        defer { desktop.close() }
        try await desktop.settle()
        desktop.dock.simulateIdle()
        try await Task.sleep(for: .milliseconds(90))
        let start = try desktop.petPoint()
        let visibleX = desktop.panel.frame.minX + desktop.dock.offset
        try desktop.send(.leftMouseDown, at: start)
        let end = CGPoint(x: start.x - 100, y: start.y + 20)
        try desktop.send(.leftMouseDragged, at: end)
        try desktop.send(.leftMouseUp, at: end)
        let home = desktop.panel.frame
        #expect(abs(home.minX - (visibleX - 100)) < 1)
        // A stale update must not implicitly start another drag after release.
        desktop.dock.dragPet(to: CGPoint(x: start.x + 100, y: start.y))
        desktop.dock.endUserDrag()
        try await desktop.settle()
        #expect(desktop.panel.frame == home)
        #expect(desktop.dock.phase == .engaged)
        #expect(desktop.dock.offset == 0)
        #expect(desktop.dock.tilt == 0)
        #expect(!desktop.dock.dragging)
    }

    @Test(arguments: [false, true])
    func firstDragFrameClearsTheEdgeClip(left: Bool) async throws {
        let desktop = try Desktop(left: left)
        defer { desktop.close() }
        try await desktop.settle()
        desktop.dock.beginIdle()
        try await desktop.settle()
        let start = try desktop.petPoint()
        try desktop.send(.leftMouseDown, at: start)
        try desktop.send(.leftMouseDragged, at: CGPoint(x: start.x + (left ? 12 : -12), y: start.y))

        // Inspect the view tree before another run-loop turn can repair a stale drawing.
        let region = try #require(desktop.panel.petInput)
        let rect = region.convert(region.bounds, to: nil)
        #expect(abs(rect.midX - desktop.panel.frame.width / 2) < 0.01)
        #expect(region.visibleRect.contains(region.bounds))
    }

    @Test func feedingDefersRetreatThenWindowGlidesToTheEdge() async throws {
        let desktop = try Desktop()
        defer { desktop.close() }
        try await desktop.settle()
        let home = desktop.panel.frame
        desktop.pet.feed()
        try await Task.sleep(for: .milliseconds(60))
        desktop.dock.update(at: Date().addingTimeInterval(60))
        #expect(desktop.dock.phase == .engaged)
        #expect(desktop.panel.frame == home)
        desktop.pet.cancelActivity()
        let screen = try #require(desktop.panel.screen)
        let target = EdgeDockGeometry.dockFrame(home: home, visibleScreen: screen.visibleFrame)
        var samples: [CGFloat] = []
        for _ in 0..<60 {
            try await Task.sleep(for: .milliseconds(16))
            let progress = (desktop.panel.frame.minX + desktop.dock.offset - home.minX) / (target.minX + 95 - home.minX)
            samples.append(progress)
            // Clipping starts at the screen edge, while the visible pet keeps moving.
            if desktop.panel.frame.maxX < screen.visibleFrame.maxX - 1 {
                #expect(desktop.dock.offset == 0)
            }
        }
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            #expect(samples.contains { $0 > 0.05 && $0 < 0.95 })
        }
        #expect(zip(samples, samples.dropFirst()).allSatisfy { $0 <= $1 })
        #expect(desktop.dock.phase == .tucked)
        #expect(desktop.panel.frame == target)
        #expect(abs(desktop.dock.tilt) <= 4)
    }

    @Test(arguments: [false, true])
    func centerToEdgeAndBackKeepsPetWholeUntilTheScreenEdge(left: Bool) async throws {
        let desktop = try Desktop(left: left)
        defer { desktop.close() }
        let screen = try #require(desktop.panel.screen).visibleFrame
        var home = desktop.panel.frame
        home.origin.x = left ? screen.midX - home.width - 20 : screen.midX + 20
        desktop.dock.repositionHome(home)
        try await desktop.settle()

        for returning in [false, true] {
            if returning { desktop.dock.interact() }
            else { desktop.dock.simulateIdle() }
            var largestOffsetAwayFromEdge: CGFloat = 0
            var clippedAwayFromEdge = false
            for _ in 0..<60 {
                try await Task.sleep(for: .milliseconds(16))
                desktop.panel.contentView?.layoutSubtreeIfNeeded()
                let frame = desktop.panel.frame
                if frame.minX > screen.minX + 1 && frame.maxX < screen.maxX - 1 {
                    largestOffsetAwayFromEdge = max(largestOffsetAwayFromEdge, abs(desktop.dock.offset))
                    let region = try #require(desktop.panel.petInput)
                    clippedAwayFromEdge = clippedAwayFromEdge || !region.visibleRect.contains(region.bounds)
                }
            }
            #expect(largestOffsetAwayFromEdge == 0)
            #expect(!clippedAwayFromEdge)
        }
        #expect(desktop.panel.frame == home)
    }
}
