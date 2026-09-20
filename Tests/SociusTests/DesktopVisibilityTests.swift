import AppKit
import SwiftUI
import Testing
@testable import Socius

@MainActor @Suite(.serialized) struct DesktopVisibilityTests {
    @Test func fullscreenAndImmersiveVideoHideThePetButOrdinaryAutoHideDoesNot() {
        #expect(DesktopVisibilityController.shouldHide(for: [.fullScreen]))
        #expect(DesktopVisibilityController.shouldHide(for: [.hideMenuBar, .hideDock]))
        #expect(DesktopVisibilityController.shouldHide(for: [.autoHideMenuBar, .autoHideDock]))
        #expect(!DesktopVisibilityController.shouldHide(for: []))
        #expect(!DesktopVisibilityController.shouldHide(for: [.autoHideDock]))
        #expect(!DesktopVisibilityController.shouldHide(for: [.autoHideMenuBar]))
    }

    @Test func fullscreenBoundsIncludeNegativeOriginDisplaysButExcludeOrdinaryMaximizedWindows() {
        for display in [CGRect(x: 0, y: 0, width: 2560, height: 1440), CGRect(x: -1440, y: -258, width: 1440, height: 2560)] {
            #expect(DesktopVisibilityController.fillsDisplay(display, display: display))
            #expect(!DesktopVisibilityController.fillsDisplay(display.insetBy(dx: 0, dy: 25), display: display))
            #expect(!DesktopVisibilityController.fillsDisplay(display.offsetBy(dx: display.width, dy: 0), display: display))
            #expect(!DesktopVisibilityController.fillsDisplay(CGRect(x: display.minX, y: display.minY, width: display.width, height: 44), display: display))
        }
    }

    @Test func fullscreenClosesPocketRejectsLateRequestsAndRestoresPetInPlace() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("FullscreenTests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let hub = ToolHub(store: ToolStore(directory: directory))
        let model = PetModel()
        let presence = EdgeDockController(model: model, reduceMotion: { true })
        let panel = PetPanel(contentRect: CGRect(origin: CGPoint(x: 500, y: 400), size: model.metrics.panelSize), styleMask: .borderless, backing: .buffered, defer: false)
        let host = PetHostingView(rootView: DesktopPetView(model: model, presence: presence, hub: hub))
        panel.contentView = host
        presence.start(window: panel)
        defer { presence.stop(); panel.orderOut(nil) }
        panel.orderFrontRegardless()
        host.layoutSubtreeIfNeeded()
        hub.openRequest += 1
        try await Task.sleep(for: .milliseconds(200))
        let pocket = try #require(panel.childWindows?.first)
        #expect(pocket.isVisible)
        let initialFrame = panel.frame
        let visibility = DesktopVisibilityController(window: panel, model: model, presence: presence, hub: hub)
        visibility.setSuppressed(true)
        #expect(!panel.isVisible)
        #expect(!pocket.isVisible)
        #expect(model.desktopSuppressed)
        hub.openRequest += 1
        hub.store.setExternalFilePicker(true)
        hub.store.setExternalFilePicker(false)
        presence.update(at: Date().addingTimeInterval(3600))
        try await Task.sleep(for: .milliseconds(200))
        #expect(panel.childWindows?.isEmpty != false)
        #expect(panel.frame == initialFrame)
        #expect(presence.reminder == nil)
        visibility.setSuppressed(false)
        try await Task.sleep(for: .milliseconds(200))
        #expect(panel.isVisible)
        #expect(panel.frame == initialFrame)
        #expect(panel.childWindows?.isEmpty != false)
        #expect(model.fullness == 75)
        #expect(model.happiness == 80)
        // An introduction already owns the pet; exiting fullscreen must not
        // create a second desktop copy behind it.
        visibility.setSuppressed(true)
        model.onboardingActive = true
        visibility.setSuppressed(false)
        #expect(!panel.isVisible)
    }
}
