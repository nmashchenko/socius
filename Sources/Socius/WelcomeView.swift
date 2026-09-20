import SwiftUI
import AppKit

private struct WelcomeBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

struct WelcomeView: View {
    let model: PetModel
    let finish: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var arrived = CommandLine.arguments.contains("--render-preview")
    @State private var greeting = CommandLine.arguments.contains("--render-preview")
    @State private var finished = false
    @State private var exiting = false
    private var gentle: Bool { reduceMotion || model.quiet }
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                WelcomeBackdrop().overlay(Palette.cream.opacity(0.25)).ignoresSafeArea()
                    .opacity(exiting ? 0 : 1)
                VStack(spacing: 8) {
                    Text("Hello, I’m \(model.displayName).")
                        .font(.system(size: 30, weight: .medium, design: .serif))
                    Text("Your little desktop helper.\nClick me anytime to see what I can do.")
                        .font(.system(size: 15)).multilineTextAlignment(.center)
                        .foregroundStyle(Palette.muted)
                }
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2 - 145)
                .opacity(greeting && !exiting ? 1 : 0)
                CreatureView(model: model, size: 140, idleMotion: false, walking: arrived && !gentle)
                    .offset(x: arrived || gentle ? 0 : -geometry.size.width * 0.6)
                    .opacity(arrived ? 1 : 0)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                    .onTapGesture(perform: complete)
                Button("Let’s go", action: complete)
                    .buttonStyle(PocketButtonStyle(prominent: true))
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2 + 130)
                    .opacity(greeting && !exiting ? 1 : 0).disabled(!greeting || finished)
                VStack {
                    HStack { Spacer(); Button("Skip", action: complete).buttonStyle(PocketButtonStyle(compact: true)) }
                    Spacer()
                }.padding(28).opacity(exiting ? 0 : 1)
            }.foregroundStyle(Palette.ink)
        }.preferredColorScheme(.light)
        .onExitCommand(perform: complete)
        .task {
            withAnimation(gentle ? .easeOut(duration: 0.2) : .timingCurve(0.77, 0, 0.175, 1, duration: 1.2)) { arrived = true }
            do {
                try await Task.sleep(for: .milliseconds(gentle ? 200 : 1200))
                withAnimation(.easeOut(duration: 0.2)) { greeting = true }
                guard !finished else { return }
                try await Task.sleep(for: .seconds(7))
                complete()
            } catch { }
        }
    }
    private func complete() {
        guard !finished else { return }
        finished = true
        let settling = !greeting && !gentle
        withAnimation(.easeOut(duration: 0.2)) { exiting = true }
        Task {
            try? await Task.sleep(for: .milliseconds(settling ? 1200 : 200))
            finish()
        }
    }
}
