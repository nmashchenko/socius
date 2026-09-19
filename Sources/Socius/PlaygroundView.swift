import SwiftUI

struct CareButton: View {
    let title: String
    let icon: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 18, weight: .regular)).frame(height: 22)
                Text(title).font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(Palette.ink).frame(maxWidth: .infinity).padding(.vertical, 13)
            .background(Palette.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 15))
        }.buttonStyle(.plain)
    }
}

struct PlaygroundView: View {
    @State private var model = PetModel()
    @State private var presence = PlaygroundPresence()
    @State private var showingOnboarding = false
    @State private var simulatingIdle = false
    @State private var selectedTool: PocketTool?
    @State private var petPosition = CGSize.zero
    @GestureState private var drag = CGSize.zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(spacing: 0) {
            ScrollView { sidebar }.frame(width: 252)
                .background(Color(red: 0.93, green: 0.93, blue: 0.87))
            Rectangle().fill(Palette.ink.opacity(0.08)).frame(width: 1)
            VStack(alignment: .leading, spacing: 24) {
                Text("Playground").font(.system(size: 28, weight: .medium, design: .serif)).foregroundStyle(Palette.ink)
                Text("Preview your pet and try its controls.").font(.system(size: 12)).foregroundStyle(Palette.muted)
                Group {
                    Button { showingOnboarding = true } label: {
                        Label("Replay onboarding", systemImage: "arrow.counterclockwise")
                    }
                }
                stage
                Spacer(minLength: 0)
                HStack {
                    Circle().fill(Palette.green).frame(width: 5, height: 5)
                    Text("Developer playground · isolated preview").font(.system(size: 11)).foregroundStyle(Palette.muted)
                    Spacer()

                }
            }.padding(32)
        }
        .alert("Tool selected", isPresented: Binding(get: { selectedTool != nil }, set: { if !$0 { selectedTool = nil } })) {
            Button("OK") { selectedTool = nil }
        } message: {
            Text("\(selectedTool?.rawValue ?? "Tool") selected in the preview. Use the desktop pocket for live tools and saved data.")
        }
        .sheet(isPresented: $showingOnboarding) {
            WelcomeView(model: model) { showingOnboarding = false; presence.simulateIdle() }
                .frame(width: 760, height: 560)
        }
        .task {
            while !Task.isCancelled {
                if simulatingIdle { presence.tick(held: false) }
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
            }
        }
        .background(Palette.cream)
        .preferredColorScheme(.light)
        .buttonStyle(PocketButtonStyle(compact: true))
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 9) {
                Image(systemName: "leaf.fill").font(.system(size: 19)).foregroundStyle(Palette.green)
                Text("socius").font(.system(size: 25, weight: .semibold, design: .rounded)).foregroundStyle(Palette.ink)
            }.padding(.bottom, 8)
            VStack(alignment: .leading, spacing: 12) {
                sectionLabel("PET")
                Text(model.displayName).font(.system(size: 22, weight: .medium, design: .serif))
                Text("Eight little arms. A little attitude.").font(.system(size: 12)).foregroundStyle(Palette.muted)
            }
            VStack(alignment: .leading, spacing: 12) {
                sectionLabel("NEEDS")
                needMeter("Full tummy", value: model.fullness, icon: "fork.knife")
                needMeter("Good spirits", value: model.happiness, icon: "heart")
                Text(model.toolsAvailable ? "Feeling helpful. The pocket is open for business." : "On a tiny strike. Care first, shortcuts after.")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 10) {
                sectionLabel("PREVIEW A MOOD")
                Text("Changes only this preview")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
                HStack(spacing: 6) {
                    ForEach([PetModel.Mood.content, .hungry, .grumpy], id: \.rawValue) { mood in
                        Button(mood == .content ? "Ready" : mood.rawValue) { model.preview(mood) }
                            .buttonStyle(PocketButtonStyle(compact: true))
                    }
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                sectionLabel("ACTIVITIES")
                HStack(spacing: 8) {
                    CareButton(title: "Pet", icon: "hand.draw", action: model.pet)
                    CareButton(title: "Snack", icon: "fork.knife", action: model.feed)
                }
                HStack(spacing: 8) {
                    CareButton(title: "Play", icon: "sparkles", action: { model.startShellGame() })
                    CareButton(title: model.mood == .sleeping ? "Wake" : "Nap", icon: "moon", action: model.sleep)
                }
            }
            Button("Simulate neglected") {
                model.preview(.hungry); model.happiness = 10
            }
            Group {
                VStack(alignment: .leading, spacing: 10) {
                    sectionLabel("PREVIEW INACTIVITY")
                    HStack {
                        Button("Go idle now") { simulatingIdle = true; presence.simulateIdle() }
                            .disabled(presence.phase != .engaged)
                        Button("Return") { simulatingIdle = false; presence.interact() }
                    }
                    Button("Show reminder") { presence.simulateReminder() }
                        .disabled(![.tucked, .peeking].contains(presence.phase))
                    Text("State: \(String(describing: presence.phase))")
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(Palette.muted)
                    DeveloperRuntimeView(idleSeconds: $presence.idleSeconds, peekSeconds: $presence.peekSeconds)
                    Text("Manual state checks only. The preview stays visible; the desktop pet is unchanged.")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
            }
            Button { model.quiet.toggle() } label: {
                HStack {
                    Text("Quiet mode").font(.system(size: 12))
                    Spacer()
                    ZStack(alignment: model.quiet ? .trailing : .leading) {
                        Capsule().fill(model.quiet ? Palette.green : Palette.muted.opacity(0.3))
                        Circle().fill(.white).padding(3)
                    }.frame(width: 32, height: 20)
                }.foregroundStyle(Palette.ink)
            }.buttonStyle(.plain).accessibilityLabel("Quiet mode").accessibilityValue(model.quiet ? "On" : "Off")
            Text("Less movement, same company. System Reduce Motion is respected too.").font(.system(size: 11)).foregroundStyle(Palette.muted).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            HStack(spacing: 7) {
                Circle().fill(model.mood == .sleeping ? Palette.muted : Palette.green).frame(width: 6, height: 6)
                Text(model.mood.rawValue).font(.system(size: 11, weight: .medium))
            }.foregroundStyle(Palette.muted)
        }.padding(24).background(Color(red: 0.93, green: 0.93, blue: 0.87))
    }
    private var stage: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24).fill(Color(red: 0.91, green: 0.92, blue: 0.85))
            Canvas { context, size in
                for x in stride(from: 16.0, to: size.width, by: 24) {
                    for y in stride(from: 16.0, to: size.height, by: 24) {
                        context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.5, height: 1.5)), with: .color(Palette.green.opacity(0.16)))
                    }
                }
            }.clipShape(RoundedRectangle(cornerRadius: 24))
            VStack {
                HStack {
                    Text("PREVIEW").font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(1.4).foregroundStyle(Palette.muted)
                    Spacer()
                    Image(systemName: "sun.max").foregroundStyle(Palette.muted)
                }.opacity(model.panelOpen ? 0 : 1)
                Spacer()
                HStack {
                    Text("drag to find a cozy spot").font(.system(size: 11, design: .serif)).italic().foregroundStyle(Palette.muted)
                    Spacer()
                    Button("Open pocket") { model.openPocket() }
                        .buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.ink)
                        .padding(.horizontal, 14).padding(.vertical, 9).background(.white.opacity(0.65), in: Capsule())
                        .opacity(model.panelOpen ? 0 : 1).allowsHitTesting(!model.panelOpen)
                }
            }.padding(22)
            HStack(spacing: 16) {
                VStack(spacing: 10) {
                    SpeechBubble(text: model.speech).frame(width: model.panelOpen ? 150 : 205)
                    InteractivePet(model: model, size: model.panelOpen ? 120 : 145, clicked: {
                        model.pet(); model.panelOpen = true
                    })
                    if model.shellGameActive { ShellGameView(model: model) }
                    CareTray(model: model, pocketAction: nil)
                    Text(model.displayName.uppercased()).font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(2).foregroundStyle(Palette.muted)
                }
                .frame(width: model.panelOpen ? 150 : 220)
                .offset(x: model.panelOpen ? 0 : petPosition.width + drag.width, y: model.panelOpen ? 0 : petPosition.height + drag.height)
                .simultaneousGesture(DragGesture(minimumDistance: 8).updating($drag) { value, state, _ in
                    if !model.panelOpen && model.offering == nil { state = value.translation }
                }.onEnded { value in
                    guard !model.panelOpen, model.offering == nil else { return }
                    petPosition.width = min(140, max(-140, petPosition.width + value.translation.width))
                    petPosition.height = min(25, max(-20, petPosition.height + value.translation.height))
                })
                if model.panelOpen {
                    PocketView(model: model, close: { model.panelOpen = false }, openTool: { selectedTool = $0 })
                        .frame(maxWidth: .infinity)
                        .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .leading)))
                }
            }.padding(.horizontal, 24)

                .animation(reduceMotion || model.quiet ? nil : .timingCurve(0.23, 1, 0.32, 1, duration: 0.2), value: model.panelOpen)
        }.frame(height: 380).clipped()
    }
    private func needMeter(_ title: String, value: Double, icon: String) -> some View {
        VStack(spacing: 6) {
            HStack {
                Label(title, systemImage: icon)
                Spacer()
                Text("\(Int(value))%").monospacedDigit()
            }.font(.system(size: 11)).foregroundStyle(Palette.ink)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.green.opacity(0.13))
                    Capsule().fill(value <= 20 ? Palette.peach : Palette.green).frame(width: geometry.size.width * max(0, min(100, value)) / 100)
                }
            }.frame(height: 5).accessibilityLabel(title).accessibilityValue("\(Int(value)) percent")
        }
    }
    private func sectionLabel(_ text: String) -> some View {
        Text(text).font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(1.3).foregroundStyle(Palette.muted)
    }
}

/// Preview-only timing; never holds or moves a desktop window.
@Observable final class PlaygroundPresence {
    enum Phase { case engaged, tucked, peeking }
    private(set) var phase: Phase = .engaged
    var idleSeconds: Double = 30
    var peekSeconds: Double = 300
    private var changed = Date()
    private var wasHeld = false
    func interact() { phase = .engaged; changed = Date() }
    func simulateIdle() { phase = .tucked; changed = Date() }
    func simulateReminder() { phase = .peeking; changed = Date() }
    func tick(held: Bool, now: Date = Date()) {
        if held { interact(); wasHeld = true; return }
        if wasHeld { wasHeld = false; simulateIdle(); return }
        let elapsed = now.timeIntervalSince(changed)
        switch phase {
        case .engaged: if elapsed >= max(1, idleSeconds) { simulateIdle() }
        case .tucked: if elapsed >= max(1, peekSeconds) { simulateReminder() }
        case .peeking: if elapsed >= 3 { simulateIdle() }
        }
    }
}
