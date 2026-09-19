import SwiftUI

struct InteractivePet: View {
    let model: PetPrototype
    var size: CGFloat = 140
    var clicked: (() -> Void)? = nil
    var idleMotion = true
    var shyEdge: Bool? = nil
    @State private var targeted = false
    var body: some View {
        CreatureView(model: model, size: size, idleMotion: idleMotion, shyEdge: shyEdge)
            .allowsWindowActivationEvents()
            .background {
                if targeted {
                    RoundedRectangle(cornerRadius: 24).strokeBorder(Palette.green.opacity(0.7), style: StrokeStyle(lineWidth: 2, dash: [4, 4]))
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { if let clicked { clicked() } else { model.acceptOffering() } }
            .dropDestination(for: String.self) { items, _ in
                guard let item = items.first else { return false }
                return model.receive(item)
            } isTargeted: { targeted = $0 }
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(model.offering == nil ? "Pet Mochi" : "Accept the offered item")
            .accessibilityAction { if let clicked { clicked() } else { model.acceptOffering() } }
    }
}

struct CareTray: View {
    let model: PetPrototype
    var pocketAction: (() -> Void)?
    var afterAction: () -> Void = {}
    var body: some View {
        HStack(spacing: 8) {
            action("Feed", "fork.knife") { model.feed(); afterAction() }
                .help("Feed Mochi: \(model.species.foodName)")
            action("Play", "sparkles") { model.startShellGame(); afterAction() }
                .help("\(model.species.gameName): find the pearl")
            action(model.mood == .sleeping ? "Wake" : "Sleep", model.mood == .sleeping ? "sun.max" : "moon") { model.sleep(); afterAction() }
            if let pocketAction { action("Tools", "square.grid.2x2", perform: pocketAction) }
        }
    }
    private func action(_ title: String, _ icon: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 15, weight: .medium)).frame(width: 22, height: 22)
                Text(title).font(.system(size: 10, weight: .medium))
            }.foregroundStyle(Palette.ink).frame(maxWidth: .infinity).padding(.vertical, 10)
                .background(Palette.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain)
    }
}

struct SpeechBubble: View {
    let text: String
    var tailPosition: CGFloat = 0.5
    var body: some View {
        Text(text).font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(Palette.ink).multilineTextAlignment(.center)
            .padding(.horizontal, 12).padding(.vertical, 10)
            .frame(maxWidth: 200)
            .background(Palette.cream, in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                GeometryReader { geometry in
                    Path { path in
                    path.move(to: CGPoint(x: 0, y: 0)); path.addLine(to: CGPoint(x: 7, y: 8)); path.addLine(to: CGPoint(x: 14, y: 0)); path.closeSubpath()
                    }.fill(Palette.cream).frame(width: 14, height: 8)
                        .position(x: geometry.size.width * tailPosition, y: geometry.size.height + 3)
                }.allowsHitTesting(false)
            }
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel("Mochi says: \(text)")
    }
}

struct ShellGameView: View {
    let model: PetPrototype
    var body: some View {
        HStack(spacing: 9) {
            ForEach(0..<3) { index in
                Button { model.chooseShell(index) } label: {
                    PixelProp(kind: .shell).frame(width: 36, height: 32)
                        .opacity(model.emptyShells.contains(index) ? 0.25 : 1)
                }.buttonStyle(.plain).disabled(model.emptyShells.contains(index))
                    .accessibilityLabel("Shell \(index + 1)")
            }
        }.padding(.top, 2)
    }
}

struct PocketView: View {
    @Bindable var model: PetPrototype
    let close: () -> Void
    var nativePopover = false
    var openTool: ((PocketTool) -> Void)? = nil
    var hub: ToolHub? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.pocketAttachedOnRight) private var attachedOnRight
    @State private var homeHeight: CGFloat = 310
    private let tools: [(String, String)] = [("Shelf", "square.stack.3d.up"), ("Clipboard", "doc.on.clipboard"), ("Music", "music.note"), ("Snippets", "text.quote"), ("Notes", "note.text"), ("AI Credits", "chart.bar"), ("Layouts", "rectangle.3.group")]
    var body: some View {
        if nativePopover {
            ZStack(alignment: attachedOnRight ? .trailing : .leading) {
                if let hub, hub.showingTool {
                    PocketToolView(hub: hub, pet: model, back: { hub.showingTool = false; hub.store.notice = nil }, close: close)
                        .frame(width: 420, height: hub.toolHeight)
                        .transition(PocketMotion.page(forward: true, reduced: reduceMotion || model.quiet))
                } else {
                    home
                        .frame(width: 340).fixedSize(horizontal: false, vertical: true)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { homeHeight = $0; hub?.pocketHomeHeight = $0 }
                        .transition(PocketMotion.page(forward: false, reduced: reduceMotion || model.quiet))
                }
            }
            .frame(width: hub?.showingTool == true ? 420 : 340, height: hub?.showingTool == true ? (hub?.toolHeight ?? 450) : homeHeight)
            .background(Palette.cream, in: RoundedRectangle(cornerRadius: 20))
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: .black.opacity(0.14), radius: 12, y: 4)
            .overlay(alignment: attachedOnRight ? .trailing : .leading) {
                PocketTail().fill(Palette.cream).frame(width: 9, height: 16)
                    .rotationEffect(.degrees(attachedOnRight ? 0 : 180))
                    .offset(x: attachedOnRight ? 8 : -8)
            }
            .animation(reduceMotion || model.quiet ? .easeOut(duration: 0.12) : PocketMotion.animation, value: hub?.showingTool)
            .environment(\.pocketQuiet, model.quiet)
        } else {
            home
        }
    }
    private var home: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Hey, friend.").font(.system(size: 19, weight: .medium, design: .serif))
                Spacer()
                Button(action: close) { Image(systemName: "xmark").font(.system(size: 11)).frame(width: 24, height: 24) }
                    .buttonStyle(.plain).accessibilityLabel("Close pocket")
            }
            Label(model.moodLabel, systemImage: model.toolsAvailable ? "heart.fill" : "heart")
                .font(.system(size: 11)).foregroundStyle(Palette.muted)
                .help("Fullness: \(Int(model.fullness))% · Spirits: \(Int(model.happiness))%")
            CareTray(model: model, afterAction: close)
            HStack {
                Text("POCKET").font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(1)
                Spacer()
                Text(model.toolsAvailable ? "Ready to help" : "Care first, tools after").font(.system(size: 10))
            }.foregroundStyle(Palette.muted)
            if model.toolsAvailable {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                ForEach(tools, id: \.0) { name, icon in
                    Button {
                        model.selectedTool = name
                        if let tool = PocketTool(rawValue: name) {
                            if let hub { hub.selected = tool; hub.store.notice = nil; hub.showingTool = true }
                            else if let openTool { openTool(tool) }
                        }
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: icon).font(.system(size: 15)).frame(height: 20)
                            Text(name).font(.system(size: 9))
                        }.frame(maxWidth: .infinity).padding(.vertical, 9)
                            .background(Color.white.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain).disabled(!model.toolsAvailable)
                }
            }
            } else {
                Text(model.fullness <= 20 ? "My tummy’s empty. A little shrimp before we work?" : "I’m feeling low. Find a pearl with me?")
                    .font(.system(size: 12, design: .rounded)).foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true).padding(.vertical, 8)
            }
        }.foregroundStyle(Palette.ink).padding(18)
            .background {
                if nativePopover { Palette.cream }
                else { RoundedRectangle(cornerRadius: 20).fill(Palette.cream) }
            }
            .preferredColorScheme(.light)
    }
}

struct DesktopPetView: View {
    @Bindable var model: PetPrototype
    let presence: EdgeDockController
    var openStudio: (() -> Void)? = nil
    let hub: ToolHub
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pocketOpen = false
    @State private var waitingForReturn = false
    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                Color.clear
                if presence.reminder != nil || model.shellGameActive || model.offering != nil || [.eating, .playing].contains(model.mood) {
                    SpeechBubble(text: presence.reminder ?? model.speech,
                                 tailPosition: presence.reminder == nil ? 0.5 : presence.leftEdge ? 0.12 : 0.88)
                        .padding(.bottom, 2)
                        .offset(x: presence.reminder == nil ? 0 : -presence.offset)
                        .transition(.opacity)
                }
            }.frame(height: 70)
            InteractivePet(model: model, size: 140, clicked: {
                presence.interact()
                if model.offering != nil { model.acceptOffering() }
                else { model.pet(); hub.showingTool = false; requestPocket() }
            }, idleMotion: presence.phase == .engaged,
               shyEdge: [.tucked, .peeking].contains(presence.phase) ? presence.leftEdge : nil)
                .rotationEffect(.degrees([.tucked, .peeking].contains(presence.phase) && model.mood != .sleeping ? (presence.leftEdge ? 7 : -7) : 0))
                .onHover { presence.hover($0) }
                .background(AnchoredPocket(isPresented: $pocketOpen, model: model, hub: hub))
                .contextMenu {
                    Button("Feed shrimp", action: model.feed)
                    Button("Play shell hunt") { model.startShellGame() }
                    Button(model.mood == .sleeping ? "Wake up" : "Tuck in", action: model.sleep)
                    Divider()
                    Button(presence.enabled ? "Keep Mochi here" : "Auto-hide at the edge") { presence.enabled.toggle() }
                    if let openStudio {
                        Button("Interaction playground", action: openStudio)
                    }
                }
            ZStack {
                Color.clear
                if model.shellGameActive { ShellGameView(model: model) }
            }.frame(height: 40)
        }.frame(width: 240, height: 270)
            .offset(x: presence.offset)
            .animation(reduceMotion || model.quiet ? nil : .spring(duration: 0.28, bounce: 0.12), value: presence.offset)
            .frame(width: 240, height: 270).clipped()
            .animation(.easeOut(duration: 0.15), value: presence.reminder)
            .onChange(of: pocketOpen) {
                presence.menuOpen = pocketOpen || hub.store.isChoosingFiles
                if presence.menuOpen { presence.interact() }
                else { presence.pocketClosed() }
            }
            .onChange(of: hub.store.isChoosingFiles) { presence.menuOpen = pocketOpen || hub.store.isChoosingFiles }
            .onChange(of: hub.store.filePickerFinished) { presence.interact(); pocketOpen = true }
            .onChange(of: presence.phase) {
                if waitingForReturn && presence.phase == .engaged {
                    waitingForReturn = false
                    pocketOpen = true
                }
            }
            .onChange(of: hub.openRequest, initial: true) {
                guard hub.openRequest > 0 else { return }
                presence.interact(); requestPocket()
            }
            .onExitCommand { pocketOpen = false; model.offering = nil; model.shellGameActive = false }
    }
    private func requestPocket() {
        if presence.phase == .engaged { pocketOpen = true }
        else { waitingForReturn = true }
    }
}
