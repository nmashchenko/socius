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
                VStack(spacing: 20) {
                    VStack(spacing: 8) {
                        Text("Hello, I’m \(model.displayName).")
                            .font(.system(size: 30, weight: .medium, design: .serif))
                        Text("Your little desktop helper.\nClick me anytime to see what I can do.")
                            .font(.system(size: 15)).multilineTextAlignment(.center)
                            .foregroundStyle(Palette.muted)
                    }.opacity(greeting ? 1 : 0)
                    CreatureView(model: model, size: 160, idleMotion: false)
                        .offset(x: arrived || gentle ? 0 : -geometry.size.width * 0.6,
                                y: arrived || gentle ? 0 : 80)
                        .opacity(arrived ? 1 : 0)
                    Button("Let’s go", action: complete)
                        .buttonStyle(PocketButtonStyle(prominent: true))
                        .opacity(greeting ? 1 : 0).disabled(!greeting)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                VStack {
                    HStack { Spacer(); Button("Skip", action: complete).buttonStyle(PocketButtonStyle(compact: true)) }
                    Spacer()
                }.padding(28)
            }.foregroundStyle(Palette.ink)
        }.preferredColorScheme(.light).opacity(exiting ? 0 : 1)
        .onExitCommand(perform: complete)
        .task {
            withAnimation(gentle ? .easeOut(duration: 0.2) : .spring(duration: 0.5, bounce: 0.2)) { arrived = true }
            do {
                try await Task.sleep(for: .milliseconds(500))
                withAnimation(.easeOut(duration: 0.2)) { greeting = true }
                try await Task.sleep(for: .seconds(7))
                complete()
            } catch { }
        }
    }
    private func complete() {
        guard !finished else { return }
        finished = true
        withAnimation(.easeOut(duration: 0.2)) { exiting = true }
        Task {
            try? await Task.sleep(for: .milliseconds(200))
            finish()
        }
    }
}
