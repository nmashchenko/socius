import SwiftUI
import AppKit
import ImageIO
import CyclopTools
import Combine

@Observable final class ToolHub {
    var selected: PocketTool = .shelf
    var showingTool = false
    var openRequest = 0
    var pocketHomeHeight: CGFloat = 310
    var toolHeight: CGFloat {
        switch selected {
        case .music: 280
        case .shelf: 260
        case .clipboard, .snippets: 290
        case .layouts:
            min(450, (store.data.layouts.isEmpty ? 320 : 300 + CGFloat(store.data.layouts.count - 1) * 90)
                + (layouts.trusted ? 0 : 48)
                + (layouts.message == nil ? 0 : 44))
        default: 450
        }
    }
    let store: ToolStore
    let spotify = SpotifyService()
    let layouts = WindowLayoutService()
    @ObservationIgnored private var pickerObservation: AnyCancellable?
    @ObservationIgnored lazy var cyclop: CyclopPocket = {
        let pocket = CyclopPocket(legacyFile: store.directory.appendingPathComponent("tools.json"))
        pickerObservation = pocket.$choosingFiles.sink { [weak self] choosing in
            self?.store.setExternalFilePicker(choosing)
        }
        return pocket
    }()
    @ObservationIgnored lazy var usage = UsageService(directory: store.directory)
    init(store: ToolStore = ToolStore()) { self.store = store }
}

/// The detail page lives inside the pet's existing anchored popover.
struct PocketToolView: View {
    @Bindable var hub: ToolHub
    let pet: PetPrototype
    let back: () -> Void
    let close: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Button(action: back) {
                    Image(systemName: "chevron.left").font(.system(size: 13, weight: .medium)).frame(width: 32, height: 36).contentShape(Rectangle())
                }.buttonStyle(.plain).help("Back to pocket").accessibilityLabel("Back to pocket")
                Label(hub.selected.rawValue, systemImage: hub.selected.icon)
                    .font(.system(size: 18, weight: .medium, design: .serif))
                Spacer()
                Button(action: close) { Image(systemName: "xmark").frame(width: 24, height: 28) }
                    .buttonStyle(.plain).accessibilityLabel("Close pocket")
            }
            Divider().opacity(0.4)
            if let error = hub.store.loadError {
                Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled)
            }
            if pet.toolsAvailable {
                content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                VStack(alignment: .leading, spacing: 18) {
                    Text(pet.fullness <= 20 ? "A little shrimp before we work?" : "Find a pearl with me first?")
                    CareTray(model: pet)
                    if pet.shellGameActive { ShellGameView(model: pet) }
                    Text("Your saved things are safe here.").font(.caption).foregroundStyle(Palette.muted)
                }
                Spacer()
            }
            if let notice = hub.store.notice {
                HStack {
                    Text(notice).font(.system(size: 11)).textSelection(.enabled)
                    Spacer()
                    Button { hub.store.notice = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
                }.padding(10).background(Palette.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }
        }.padding(18).frame(height: hub.toolHeight)
            .foregroundStyle(Palette.ink).background(Palette.cream).preferredColorScheme(.light)
            .buttonStyle(PocketButtonStyle())
    }
    @ViewBuilder private var content: some View {
        switch hub.selected {
        case .shelf, .clipboard, .snippets, .notes, .music:
            CyclopPocketPane(pocket: hub.cyclop, tool: hub.selected.rawValue).id(hub.selected)
        case .usage: UsageToolView(service: hub.usage)
        case .layouts: LayoutToolView(store: hub.store, service: hub.layouts)
        }
    }
}

private struct EmptyToolView: View {
    let icon: String
    let title: String
    let detail: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 30)).foregroundStyle(Palette.green)
            Text(title).font(.system(size: 17, weight: .medium, design: .serif))
            Text(detail).font(.system(size: 12)).foregroundStyle(Palette.muted).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(24)
    }
}

private struct UsageToolView: View {
    let service: UsageService
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Uses installed CLIs automatically. Keychain access is optional and only starts when you ask.")
                    .font(.system(size: 12)).foregroundStyle(Palette.muted)
                provider("Codex", service.codex)
                provider("Claude", service.claude)
                Text("Allowances are percentages of each provider’s limits. A missing or expired update is shown as unknown.")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
            }
        }.scrollIndicators(.hidden).task {
            await service.loadInstalledCLIs()

        }
    }

    private func provider(_ name: String, _ usage: ProviderUsage) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            let loading = name == "Codex" ? service.codexLoading : service.claudeLoading
            HStack {
                Text(name).font(.system(size: 17, weight: .medium, design: .serif))
                Spacer()
                if loading {
                    ProgressView().controlSize(.small).frame(width: 28, height: 28)
                        .accessibilityLabel("Refreshing \(name) usage")
                } else if name == "Codex" ? service.codexCLIAvailable : service.claudeCLIAvailable {
                    Button {
                        Task {
                            if name == "Codex" { await service.loadCodex() }
                            else { await service.loadClaudeCLI() }
                        }
                    } label: { Image(systemName: "arrow.clockwise").frame(width: 28, height: 28) }
                    .buttonStyle(.plain).accessibilityLabel("Refresh \(name) usage")
                }
            }
            if loading && usage.windows.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    RoundedRectangle(cornerRadius: 3).fill(Palette.ink.opacity(0.07)).frame(width: 130, height: 10)
                    RoundedRectangle(cornerRadius: 3).fill(Palette.ink.opacity(0.05)).frame(height: 5)
                    Text("Reading account limits…").font(.system(size: 11)).foregroundStyle(Palette.muted)
                }.accessibilityElement(children: .ignore).accessibilityLabel("Loading \(name) usage")
            }
            Text(name == "Codex"
                 ? "Uses your signed-in Codex CLI to read allowance limits. No conversation is started."
                 : "Reads account and model limits through your signed-in Claude CLI’s /usage command. No model request. The CLI manages its own sign-in; Socius does not read its credentials.")
                .font(.system(size: 11)).foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
            if name == "Claude" && !service.claudeCLIAvailable {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Your sign-in stays private").font(.system(size: 14, weight: .semibold))
                    Text("A one-time sync reads your Claude sign-in from Keychain and sends its token only to Anthropic over HTTPS. Socius never saves or logs it, and sends nothing to any other service.")
                        .font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                    Button("One-time Keychain sync") { Task { await service.authorizeClaude() } }
                        .buttonStyle(PocketButtonStyle(prominent: true)).disabled(service.busy)
                    Link("Or install Claude Code", destination: URL(string: "https://code.claude.com/docs/en/quickstart")!)
                }.padding(12).background(Palette.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            } else if name == "Codex" && !service.codexCLIAvailable {
                Text("Subscription limits require the Codex CLI. An API key cannot report your ChatGPT plan allowance.")
                    .font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                Link("Install Codex CLI", destination: URL(string: "https://developers.openai.com/codex/cli/")!)
            }

            ForEach(usage.windows) { window in
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(window.name)
                        Spacer()
                        Text(window.expired ? "Awaiting update" : "\(Int(window.used))% used · \(Int(window.remaining))% left")
                    }.font(.system(size: 11))
                    if !window.expired { ProgressView(value: min(100, window.used), total: 100).tint(Palette.green) }
                    if let description = window.resetDescription { Text(description).font(.system(size: 10)).foregroundStyle(Palette.muted) }
                    if let reset = window.resetsAt { Text("Resets \(reset.formatted(date: .abbreviated, time: .shortened))").font(.system(size: 10)).foregroundStyle(Palette.muted) }
                }
            }
            if !usage.message.isEmpty {
            Text(usage.message).fixedSize(horizontal: false, vertical: true).font(.system(size: 11)).foregroundStyle(Palette.muted).textSelection(.enabled)
            }
            if let updated = usage.updatedAt { Text("Received \(updated.formatted(date: .abbreviated, time: .shortened))").font(.system(size: 10)).foregroundStyle(Palette.muted) }
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct LayoutToolView: View {
    let store: ToolStore
    let service: WindowLayoutService
    @State private var name = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Arrange your apps, then save their positions. Restore opens missing apps and places their available windows; it doesn’t reopen documents or browser tabs.")
                .font(.system(size: 12)).foregroundStyle(Palette.muted)
            HStack {
                TextField("Name your layout", text: $name).textFieldStyle(.plain).font(.system(size: 12)).padding(10)
                    .background(.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
                Button("Save current") {
                    Task { if let layout = await service.capture(name: name), store.update({ $0.layouts.append(layout) }) { name = "" } }
                }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || service.busy)
            }
            if !service.trusted { Button("Allow window control…", action: service.requestAccess).font(.caption) }
            if let message = service.message {
                HStack(spacing: 8) {
                    if service.busy { ProgressView().controlSize(.small) }
                    Text(message).font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
            }
            if store.data.layouts.isEmpty {
                EmptyToolView(icon: "rectangle.3.group", title: "Everything in its place", detail: "Save a work setup and bring it back with one click.")
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(store.data.layouts) { layout in
                            HStack {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(layout.name).font(.system(size: 14, weight: .medium))
                                    Text("\(layout.windows.count) windows · " + Set(layout.windows.map(\.appName)).sorted().joined(separator: ", "))
                                        .font(.system(size: 11)).foregroundStyle(Palette.muted).lineLimit(2)
                                }
                                Spacer()
                                Button("Restore") { Task { await service.restore(layout) } }.disabled(service.busy)
                                Button { store.update { $0.layouts.removeAll { $0.id == layout.id } } } label: { Image(systemName: "trash") }.buttonStyle(PocketButtonStyle(compact: true)).help("Delete saved layout")
                            }.padding(14).background(.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
            }
        }.task {
            while !Task.isCancelled {
                service.refreshAccess()
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
        }
    }
}
