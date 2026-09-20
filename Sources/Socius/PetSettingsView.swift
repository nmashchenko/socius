import SwiftUI

struct PetSettingsView: View {
    @Bindable var model: PetModel
    var body: some View {
        VStack(alignment: .leading, spacing: PocketMetrics.sectionGap) {
            HStack(spacing: PocketMetrics.controlInset) {
                Text("Pet name").font(.system(size: 12, weight: .semibold))
                    .frame(width: 76, alignment: .leading)
                TextField("Mochi", text: $model.name)
                    .modifier(PocketInputStyle())
                    .onChange(of: model.name) { _, value in
                        if value.count > 30 { model.name = String(value.prefix(30)) }
                    }
            }
            PetAppearanceControls(model: model)
            PetShortcutControl(model: model)
            Divider().opacity(0.4)
            VStack(alignment: .leading, spacing: PocketMetrics.controlInset) {
                Text("In your pocket").font(.system(size: 12, weight: .semibold))
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: PocketMetrics.rowGap) {
                    ForEach(PocketTool.allCases.filter { $0 != .settings }) { tool in
                        Button {
                            if model.showsTool(tool.rawValue) { model.hiddenTools.insert(tool.rawValue) }
                            else { model.hiddenTools.remove(tool.rawValue) }
                        } label: {
                            HStack(spacing: PocketMetrics.rowGap) {
                                Image(systemName: tool.icon).frame(width: 16)
                                Text(tool.rawValue)
                                Spacer(minLength: 0)
                                Image(systemName: model.showsTool(tool.rawValue) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(model.showsTool(tool.rawValue) ? Palette.green : Palette.muted)
                            }
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, PocketMetrics.controlInset)
                            .frame(height: PocketMetrics.controlHeight)
                            .background(Palette.green.opacity(model.showsTool(tool.rawValue) ? 0.08 : 0.03), in: RoundedRectangle(cornerRadius: PocketMetrics.cornerRadius))
                            .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                            .accessibilityLabel(tool.rawValue)
                            .accessibilityValue(model.showsTool(tool.rawValue) ? "Shown in pocket" : "Hidden from pocket")
                            .accessibilityAddTraits(model.showsTool(tool.rawValue) ? .isSelected : [])
                    }
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: PocketMetrics.rowGap) {
                HStack {
                    Link(destination: URL(string: "https://github.com/nmashchenko/socius/issues/new")!) {
                        Label("Report a bug", systemImage: "ladybug")
                    }
                    Spacer()
                    Button { NSApp.terminate(nil) } label: { Label("Quit Socius", systemImage: "power") }
                }.buttonStyle(PocketButtonStyle(compact: true))
                Text("After quitting, reopen Socius from Applications or Spotlight.")
                    .font(.system(size: 10)).foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
