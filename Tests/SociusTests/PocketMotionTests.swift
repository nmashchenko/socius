import AppKit
import SwiftUI
import Testing
@testable import Socius

@MainActor @Suite struct PocketMotionTests {
    @Test func pocketAttachesAsChildAndCleansUpOnDismiss() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PocketHostTests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let hub = ToolHub(store: ToolStore(directory: directory))
        let model = PetModel()
        let host = NSHostingView(rootView: AnchoredPocket(isPresented: .constant(true), model: model, hub: hub))
        let window = NSWindow(contentRect: CGRect(x: 500, y: 400, width: 140, height: 140), styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        window.orderFrontRegardless()
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        #expect(window.childWindows?.count == 1)
        #expect(window.childWindows?.first?.isOpaque == false)
        host.rootView = AnchoredPocket(isPresented: .constant(false), model: model, hub: hub)
        try await Task.sleep(for: .milliseconds(100))
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
}
