import AppKit
import SwiftUI
import Testing
@testable import Socius

@MainActor @Suite(.serialized) struct WelcomeAnimationTests {
    @Test
    func tentaclesKeepMovingAfterArrivalUnlessMotionIsReduced() async throws {
        _ = NSApplication.shared
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let model = PetModel()
        let host = NSHostingView(rootView: WelcomeView(model: model, finish: {}))
        let panel = NSPanel(contentRect: CGRect(x: 200, y: 200, width: 800, height: 640), styleMask: .borderless, backing: .buffered, defer: false)
        panel.contentView = host
        panel.orderFrontRegardless()
        defer { panel.orderOut(nil); panel.contentView = nil }
        host.layoutSubtreeIfNeeded()
        // Exercise the actual entrance task and greeting transition, rather
        // than constructing a creature with its animation already enabled.
        try await Task.sleep(for: .seconds(2))
        panel.displayIfNeeded()
        func tentaclePixels() throws -> [Bool] {
            // Measure the tentacles in the composited surface at its backing scale.
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let scale = CGFloat(bitmap.pixelsWide) / host.bounds.width
            var pixels: [Bool] = []
            for y in Int(340 * scale)..<Int(390 * scale) {
                for x in Int(330 * scale)..<Int(470 * scale) {
                    let color = try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(NSColorSpace.deviceRGB))
                    // Compare only the coral sprite, excluding the translucent backdrop.
                    pixels.append(color.redComponent > 0.5 && color.redComponent - color.greenComponent > 0.12 && color.redComponent - color.blueComponent > 0.12)
                }
            }
            return pixels
        }
        let initial = try tentaclePixels()
        #expect(initial.filter { $0 }.count > 50, "The test must capture the visible pet's tentacles")
        var changed = false
        for _ in 0..<4 {
            try await Task.sleep(for: .milliseconds(350))
            if try tentaclePixels() != initial { changed = true }
        }
        #expect(changed == !reduced)
    }
}
