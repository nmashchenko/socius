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
            .background(.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 15))
        }.buttonStyle(.plain)
    }
}

struct PlaygroundView: View {
    @Bindable var model: PetPrototype
    var presence: EdgeDockController? = nil
    var openTool: ((PocketTool) -> Void)? = nil
    @State private var petPosition = CGSize.zero
    @GestureState private var drag = CGSize.zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(spacing: 0) {
            ScrollView { sidebar }.frame(width: 252)
                .background(Color(red: 0.93, green: 0.93, blue: 0.87))
            Rectangle().fill(Palette.ink.opacity(0.08)).frame(width: 1)
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("A LITTLE COMPANY").font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(2).foregroundStyle(Palette.muted)
                        Text("Meet your desk buddy.").font(.system(size: 31, weight: .medium, design: .serif)).foregroundStyle(Palette.ink)
                    }
                    Spacer()
                    Text("INTERACTION STUDY  /  03").font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundStyle(Palette.muted).padding(.top, 8)
                }
                stage
                HStack(alignment: .top, spacing: 25) {
                    explanation("01", "Make a little connection", "Click Mochi for a little love and its menu. Feed shrimp, find a pearl, or tuck it in.")
                    explanation("02", "Give it a home", "Drag your buddy to a favorite spot. The desktop pet can move independently.")
                    explanation("03", "A hand when you need it", "Open the pocket for your tools. Close it and get back to your day.")
                }
                Spacer(minLength: 0)
                HStack {
                    Circle().fill(Palette.green).frame(width: 5, height: 5)
                    Text("Developer playground · controls affect your desktop pet").font(.system(size: 11)).foregroundStyle(Palette.muted)
                    Spacer()
                    Text("A little care goes a long way.").font(.system(size: 12, design: .serif)).italic().foregroundStyle(Palette.muted)
                }
            }.padding(32)
        }
        .background(Palette.cream)
        .preferredColorScheme(.light)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 9) {
                Image(systemName: "leaf.fill").font(.system(size: 19)).foregroundStyle(Palette.green)
                Text("socius").font(.system(size: 25, weight: .semibold, design: .rounded)).foregroundStyle(Palette.ink)
            }.padding(.bottom, 8)
            VStack(alignment: .leading, spacing: 12) {
                sectionLabel("THE LITTLE DETAILS")
                Text("Mochi").font(.system(size: 22, weight: .medium, design: .serif))
                Text("Eight little arms. A little attitude.").font(.system(size: 12)).foregroundStyle(Palette.muted)
            }
            VStack(alignment: .leading, spacing: 12) {
                sectionLabel("A LITTLE GIVE & TAKE")
                needMeter("Full tummy", value: model.fullness, icon: "fork.knife")
                needMeter("Good spirits", value: model.happiness, icon: "heart")
                Text(model.toolsAvailable ? "Feeling helpful. The pocket is open for business." : "On a tiny strike. Care first, shortcuts after.")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 10) {
                sectionLabel("PREVIEW A MOOD")
                Text("Developer only · changes the desktop pet too")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
                HStack(spacing: 6) {
                    ForEach([PetPrototype.Mood.content, .hungry, .grumpy], id: \.rawValue) { mood in
                        Button(mood == .content ? "Ready" : mood.rawValue) { model.preview(mood) }
                            .buttonStyle(.plain).font(.system(size: 10, weight: .medium)).padding(.horizontal, 9).padding(.vertical, 8)
                            .background(.white.opacity(0.7), in: Capsule())
                    }
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                sectionLabel("TRY A MOMENT")
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
            if let presence {
                VStack(alignment: .leading, spacing: 10) {
                    sectionLabel("DESKTOP INACTIVITY")
                    HStack {
                        Button("Go idle now") { presence.simulateIdle() }
                            .disabled(presence.phase != .engaged)
                        Button("Return") { presence.interact() }
                    }
                    Button("Show reminder") { presence.simulateReminder() }
                        .disabled(![.tucked, .peeking].contains(presence.phase))
                    Text("State: \(String(describing: presence.phase))")
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(Palette.muted)
                    DeveloperRuntimeView(presence: presence)
                    Text("Timing overrides reset when the app restarts.")
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
                    Text("YOUR DESKTOP, A LITTLE WARMER").font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(1.4).foregroundStyle(Palette.muted)
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
                    Text("MOCHI").font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(2).foregroundStyle(Palette.muted)
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
                    PocketView(model: model, close: { model.panelOpen = false }, openTool: openTool)
                        .frame(maxWidth: .infinity)
                        .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .leading)))
                }
            }.padding(.horizontal, 24)
                .animation(reduceMotion || model.quiet ? nil : .timingCurve(0.23, 1, 0.32, 1, duration: 0.2), value: model.panelOpen)
        }.frame(height: 380)
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
    private func explanation(_ number: String, _ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(number).font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.muted)
            Text(title).font(.system(size: 13, weight: .medium, design: .serif)).foregroundStyle(Palette.ink)
            Text(detail).font(.system(size: 11)).foregroundStyle(Palette.muted).lineSpacing(4)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
