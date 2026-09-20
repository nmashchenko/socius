import AppKit
import SwiftUI
import Testing
@testable import Socius

@MainActor @Suite(.serialized) struct PocketMotionTests {
    @Test(arguments: [false, true])
    func pocketAttachesAsChildAndCleansUpOnDismiss(onRight: Bool) async throws {
        _ = NSApplication.shared
        let screen = try #require(NSScreen.main)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PocketHostTests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let hub = ToolHub(store: ToolStore(directory: directory))
        let model = PetModel()
        let host = NSHostingView(rootView: AnchoredPocket(isPresented: .constant(true), model: model, hub: hub))
        let x = onRight ? screen.visibleFrame.maxX - 164 : screen.visibleFrame.minX + 24
        let window = NSWindow(contentRect: CGRect(x: x, y: screen.visibleFrame.midY - 70, width: 140, height: 140), styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        window.orderFrontRegardless()
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        #expect(window.childWindows?.count == 1)
        #expect(window.childWindows?.first?.isOpaque == false)
        let pocket = try #require(window.childWindows?.first)
        let previousX = pocket.frame.minX
        window.setContentSize(CGSize(width: 100, height: 100))
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        // Resizing moves the anchor's right edge, while its left edge stays fixed.
        #expect(abs(pocket.frame.minX - (previousX + (onRight ? 0 : -40))) < 1)
        host.rootView = AnchoredPocket(isPresented: .constant(false), model: model, hub: hub)
        let dismissalDeadline = ContinuousClock.now.advanced(by: .seconds(2))
        while window.childWindows?.isEmpty == false, ContinuousClock.now < dismissalDeadline {
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(window.childWindows?.isEmpty != false)
        window.orderOut(nil)
    }
    @Test func rapidNavigationKeepsNativePopoverSizeStable() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PocketMotionTests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let hub = ToolHub(store: ToolStore(directory: directory))
        let model = PetModel()
        let host = NSHostingView(rootView: PocketView(model: model, close: {}, nativePopover: true, hub: hub).frame(width: 460, height: 490))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 460, height: 490), styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        let initialSize = host.fittingSize
        #expect(initialSize == CGSize(width: 460, height: 490))
        for index in 0..<24 {
            if index == 0 { hub.selected = .notes; hub.showingTool = true }
            if index == 3 { hub.showingTool = false }
            if index == 5 { hub.selected = .clipboard; hub.showingTool = true }
            if index == 8 { hub.showingTool = false }
            try await Task.sleep(for: .milliseconds(20))
            host.layoutSubtreeIfNeeded()
            #expect(host.fittingSize == initialSize)
        }
        #expect(!hub.showingTool)
        window.orderOut(nil)
    }
    @Test func onboardingClosesAnOpenPocketAndBlocksQueuedReopening() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("OnboardingPocketTests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let hub = ToolHub(store: ToolStore(directory: directory))
        let model = PetModel()
        let host = NSHostingView(rootView: AnchoredPocket(isPresented: .constant(true), model: model, hub: hub))
        let window = PetPanel(contentRect: CGRect(x: 500, y: 400, width: 140, height: 140), styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        let pocket = try #require(window.childWindows?.first)
        #expect(pocket.isVisible)
        model.onboardingActive = true
        try await Task.sleep(for: .milliseconds(100))
        #expect(!pocket.isVisible)
        #expect(window.childWindows?.isEmpty != false)
        // A stale presentation request must not bring the pocket back.
        host.rootView = AnchoredPocket(isPresented: .constant(true), model: model, hub: hub)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        #expect(window.childWindows?.isEmpty != false)
        window.suspendDesktopPresentation()
        #expect(window.contentView == nil)
        #expect(window.ignoresMouseEvents)
        #expect(!window.isVisible)
    }

}
