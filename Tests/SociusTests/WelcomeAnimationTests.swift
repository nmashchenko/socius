import AppKit
import SwiftUI
import Testing
@testable import Socius

@MainActor @Suite(.serialized) struct WelcomeAnimationTests {
    private struct WelcomeProbe: View {
        let model: PetModel
        let motionSetting: (Bool) -> Void
        @Environment(\.accessibilityReduceMotion) private var reduced
        var body: some View {
            WelcomeView(model: model, finish: {})
                .onAppear { motionSetting(reduced) }
                .onChange(of: reduced) { motionSetting(reduced) }
        }
    }

    @Test func tentaclesKeepMovingAfterArrivalUnlessMotionIsReduced() async throws {
        _ = NSApplication.shared
        let model = PetModel()
        var reducedMotion: Bool?
        let host = NSHostingView(rootView: WelcomeProbe(model: model, motionSetting: { reducedMotion = $0 }))
        let panel = NSPanel(contentRect: CGRect(x: 200, y: 200, width: 800, height: 640), styleMask: .borderless, backing: .buffered, defer: false)
        panel.contentView = host
        panel.orderFrontRegardless()
        defer { panel.orderOut(nil); panel.contentView = nil }

        func spritePixels() throws -> (head: [Bool], tentacles: [Bool]) {
            host.layoutSubtreeIfNeeded()
            panel.displayIfNeeded()
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let scale = CGFloat(bitmap.pixelsWide) / host.bounds.width
            func mask(top: Int, bottom: Int) throws -> [Bool] {
                var pixels: [Bool] = []
                for y in Int(CGFloat(top) * scale)..<Int(CGFloat(bottom) * scale) {
                    for x in Int(330 * scale)..<Int(470 * scale) {
                        let color = try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(NSColorSpace.deviceRGB))
                        // Compare only the coral sprite, excluding the translucent backdrop.
                        pixels.append(color.redComponent > 0.5 && color.redComponent - color.greenComponent > 0.12 && color.redComponent - color.blueComponent > 0.12)
                    }
                }
                return pixels
            }
            return (try mask(top: 275, bottom: 320), try mask(top: 340, bottom: 390))
        }

        // Wait for the actual entrance task and a settled head, rather than
        // assuming a busy/headless runner has rendered everything after 2 seconds.
        let deadline = ContinuousClock.now.advanced(by: .seconds(8))
        var previousHead: [Bool] = []
        var settled = 0
        var initial: [Bool] = []
        while settled < 3, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(300))
            let pixels = try spritePixels()
            let visible = pixels.head.filter { $0 }.count > 50 && pixels.tentacles.filter { $0 }.count > 50
            settled = visible && pixels.head == previousHead ? settled + 1 : 0
            previousHead = pixels.head
            initial = pixels.tentacles
        }
        try #require(settled == 3, "The actual onboarding pet must arrive and settle before measuring idle motion")
        let reduced = try #require(reducedMotion)
        var changed = false
        for _ in 0..<5 {
            try await Task.sleep(for: .milliseconds(350))
            if try spritePixels().tentacles != initial { changed = true }
        }
        #expect(changed == !reduced)
    }
}
