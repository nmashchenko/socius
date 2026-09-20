import SwiftUI

struct InteractivePet: View {
    let model: PetModel
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
            .accessibilityHint(model.offering == nil ? "Pet \(model.displayName)" : "Accept the offered item")
            .accessibilityAction { if let clicked { clicked() } else { model.acceptOffering() } }
    }
}

struct CareTray: View {
    let model: PetModel
    var pocketAction: (() -> Void)?
    var afterAction: () -> Void = {}
    var body: some View {
        HStack(spacing: 8) {
            action("Feed", "fork.knife") { model.feed(); afterAction() }
                .help("Feed \(model.displayName): \(model.species.foodName)")
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
            .accessibilityLabel("Pet says: \(text)")
    }
}

struct ShellGameView: View {
    let model: PetModel
    var body: some View {
        HStack(spacing: 9) {
            ForEach(0..<3) { index in
                Button { model.chooseShell(index) } label: {
                    PixelProp(kind: .shell).frame(width: 36, height: 32)
                        .opacity(model.emptyShells.contains(index) ? 0.25 : 1)
                        .contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .allowsWindowActivationEvents()
                    .disabled(model.emptyShells.contains(index))
                    .accessibilityLabel("Shell \(index + 1)")
            }
        }.padding(.top, 2)
    }
}

struct PocketView: View {
    @Bindable var model: PetModel
    let close: () -> Void
    var nativePopover = false
    var openTool: ((PocketTool) -> Void)? = nil
    var hub: ToolHub? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.pocketAttachedOnRight) private var attachedOnRight
    @State private var homeHeight: CGFloat = 310
    private let tools: [(String, String)] = [("Shelf", "square.stack.3d.up"), ("Clipboard", "doc.on.clipboard"), ("Music", "music.note"), ("Snippets", "text.quote"), ("Notes", "note.text"), ("AI Credits", "chart.bar"), ("Layouts", "rectangle.3.group"), ("Settings", "gearshape")]
    var body: some View {
        if nativePopover {
            ZStack(alignment: attachedOnRight ? .trailing : .leading) {
                if let hub, hub.showingTool {
                    PocketToolView(hub: hub, pet: model, back: { hub.showingTool = false; hub.store.notice = nil }, close: close)
                        .frame(width: 420, height: hub.toolHeight)
                        .transition(PocketMotion.page(forward: true, reduced: reduceMotion))
                } else {
                    home
                        .frame(width: 340).fixedSize(horizontal: false, vertical: true)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { homeHeight = $0; hub?.pocketHomeHeight = $0 }
                        .transition(PocketMotion.page(forward: false, reduced: reduceMotion))
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
            .animation(reduceMotion ? .easeOut(duration: 0.12) : PocketMotion.animation, value: hub?.showingTool)
        } else {
            home
        }
    }
    private var home: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Hey, friend.").font(.system(size: 19, weight: .medium, design: .serif))
                Spacer()
                Button(action: close) { Image(systemName: "xmark").font(.system(size: 11)).frame(width: 36, height: 36).contentShape(Rectangle()) }
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
                ForEach(tools.filter { model.showsTool($0.0) }, id: \.0) { name, icon in
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
    @Bindable var model: PetModel
    let presence: EdgeDockController
    var openStudio: (() -> Void)? = nil
    let hub: ToolHub
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
            }.frame(height: model.metrics.speechHeight)
            InteractivePet(model: model, size: model.metrics.size, clicked: clickPet, idleMotion: presence.phase == .engaged && !presence.dragging,
               shyEdge: [.tucked, .peeking].contains(presence.phase) ? presence.leftEdge : nil)
                .rotationEffect(.degrees(model.mood != .sleeping ? presence.tilt : 0))
                .background(PetPointerInput(presence: presence, clicked: clickPet, dragBegan: {
                    waitingForReturn = false
                    setPocketOpen(false, retreatOnClose: false)
                }).frame(width: model.metrics.size, height: model.metrics.size))
                .onHover { presence.hover($0) }
                .background(AnchoredPocket(isPresented: Binding(get: { pocketOpen }, set: { setPocketOpen($0) }), model: model, hub: hub))
                .contextMenu {
                    Button("Feed shrimp", action: model.feed)
                    Button("Play shell hunt") { model.startShellGame() }
                    Button(model.mood == .sleeping ? "Wake up" : "Tuck in", action: model.sleep)
                    Divider()
                    Button(presence.enabled ? "Keep \(model.displayName) here" : "Auto-hide at the edge") { presence.enabled.toggle() }
                    if let openStudio {
                        Button("Developer dashboard", action: openStudio)
                    }
                    Divider()
                    Button("Quit Socius") { NSApp.terminate(nil) }
                }
            ZStack {
                Color.clear
                if model.shellGameActive { ShellGameView(model: model).scaleEffect(model.desktopScale) }
            }.frame(height: model.metrics.footerHeight)
        }.frame(width: model.metrics.panelSize.width, height: model.metrics.panelSize.height)
            .offset(x: presence.offset)
            .frame(width: model.metrics.panelSize.width, height: model.metrics.panelSize.height).clipped()
            // Position and pose share the display-link clock; no second SwiftUI spring.
            .onChange(of: hub.store.isChoosingFiles) { presence.menuOpen = pocketOpen || hub.store.isChoosingFiles }
            .onChange(of: hub.store.filePickerFinished) {
                guard !model.desktopSuppressed else { return }
                presence.interact(); setPocketOpen(true)
            }
            .onChange(of: presence.phase) {
                if waitingForReturn && presence.phase == .engaged {
                    waitingForReturn = false
                    setPocketOpen(true)
                }
            }
            .onChange(of: hub.dismissRequest) { setPocketOpen(false, retreatOnClose: false) }
            .onChange(of: model.desktopSuppressed) {
                if model.desktopSuppressed { setPocketOpen(false, retreatOnClose: false) }
            }
            .onChange(of: hub.openRequest, initial: true) {
                guard hub.openRequest > 0, !model.desktopSuppressed else { return }
                presence.interact(); requestPocket()
            }
            .onChange(of: model.mood) { presence.update(at: Date()) }
            .onChange(of: model.offering) { presence.update(at: Date()) }
            .onChange(of: model.shellGameActive) { presence.update(at: Date()) }
            .onExitCommand { setPocketOpen(false); model.offering = nil; model.shellGameActive = false }
    }
    private func clickPet() {
        presence.interact()
        if model.offering != nil { model.acceptOffering() }
        else { model.pet(); hub.showingTool = false; requestPocket() }
    }
    private func setPocketOpen(_ open: Bool, retreatOnClose: Bool = true) {
        guard !open || !model.desktopSuppressed else { return }
        if !open { waitingForReturn = false }
        guard pocketOpen != open else { return }
        pocketOpen = open
        presence.menuOpen = open || hub.store.isChoosingFiles
        if presence.menuOpen { presence.interact() }
        else if retreatOnClose { presence.pocketClosed() }
    }
    private func requestPocket() {
        guard !model.desktopSuppressed else { return }
        if presence.phase == .engaged { setPocketOpen(true) }
        else { waitingForReturn = true }
    }
}
