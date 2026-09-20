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
    @Bindable var model: PetModel
    @Bindable var presence: EdgeDockController
    var replayOnboarding: (() -> Void)? = nil
    var openPocket: () -> Void = {}
    var returnPet: () -> Void = {}
    var closePocket: () -> Void = {}
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Developer dashboard").font(.system(size: 27, weight: .medium, design: .serif))
                Text("These controls change the pet on your desktop.")
                    .font(.system(size: 12)).foregroundStyle(Palette.muted)
                GroupBox("Desktop pet") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(model.displayName).font(.system(size: 22, weight: .medium, design: .serif))
                        Text("Tummy: \(Int(model.fullness))% · Spirits: \(Int(model.happiness))%")
                        Text("Mood: \(model.mood.rawValue)")
                        HStack {
                            Button("Open pocket", action: openPocket)
                            Button("Bring pet back", action: returnPet)
                        }
                        if let replayOnboarding { Button("Replay onboarding", action: replayOnboarding) }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                }
                GroupBox("Care and moods") {
                    VStack(spacing: 10) {
                        HStack(spacing: 8) {
                            CareButton(title: "Pet", icon: "hand.draw", action: model.pet)
                            CareButton(title: "Snack", icon: "fork.knife", action: model.feed)
                            CareButton(title: "Play", icon: "sparkles", action: { model.startShellGame() })
                            CareButton(title: model.mood == .sleeping ? "Wake" : "Nap", icon: "moon", action: model.sleep)
                        }
                        HStack {
                            ForEach([PetModel.Mood.content, .hungry, .grumpy], id: \.rawValue) { mood in
                                Button(mood == .content ? "Ready" : mood.rawValue) { model.preview(mood) }
                            }
                            Button("Neglected") { model.preview(.hungry); model.happiness = 10 }
                        }
                    }.padding(8)
                }
                GroupBox("Inactivity") {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Auto-hide at the edge", isOn: $presence.enabled)
                        HStack {
                            Button("Go idle now") { closePocket(); presence.simulateIdle() }
                            Button("Return") { presence.interact() }
                            Button("Show reminder") { closePocket(); presence.simulateReminder() }
                        }
                        Text("State: \(String(describing: presence.phase))")
                            .font(.system(size: 11, design: .monospaced))
                        DeveloperRuntimeView(idleSeconds: $presence.idleSeconds, peekSeconds: $presence.peekSeconds)
                    }.padding(8)
                }
                PetAppearanceControls(model: model)
            }.padding(24)
                .disabled(model.desktopSuppressed || model.onboardingActive)
        }
        .font(.system(size: 12))
        .foregroundStyle(Palette.ink)
        .background(Palette.cream)
        .preferredColorScheme(.light)
        .buttonStyle(PocketButtonStyle(compact: true))
    }
}
