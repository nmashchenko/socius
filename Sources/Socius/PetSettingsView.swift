import SwiftUI

struct PetSettingsView: View {
    @Bindable var model: PetModel
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Your pet’s name").font(.system(size: 12, weight: .semibold))
                TextField("Mochi", text: $model.name)
                    .textFieldStyle(.plain).font(.system(size: 14))
                    .padding(8).background(Palette.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    .onChange(of: model.name) { _, value in
                        if value.count > 30 { model.name = String(value.prefix(30)) }
                    }
            }
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Quiet mode", isOn: $model.quiet).toggleStyle(PocketToggleStyle())
                Text("Less motion and no reminder bubbles. Respects Reduce Motion.")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
            }
            PetShortcutControl(model: model)
            VStack(alignment: .leading, spacing: 10) {
                Text("Show in pocket").font(.system(size: 12, weight: .semibold))
                LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], alignment: .leading, spacing: 10) {
                    ForEach(PocketTool.allCases.filter { $0 != .settings }) { tool in
                        Toggle(isOn: Binding(get: { model.showsTool(tool.rawValue) }, set: { visible in
                            if visible { model.hiddenTools.remove(tool.rawValue) }
                            else { model.hiddenTools.insert(tool.rawValue) }
                        })) { Label(tool.rawValue, systemImage: tool.icon) }
                        .toggleStyle(PocketToggleStyle())
                    }
                }
            }.font(.system(size: 12, weight: .semibold)).tint(Palette.green)
            Link(destination: URL(string: "https://github.com/nmashchenko/socius/issues/new")!) {
                Label("Report a bug", systemImage: "ladybug")
            }.buttonStyle(PocketButtonStyle()).help("Opens GitHub so you can review and submit your report.")
            Spacer(minLength: 0)
        }
    }
}
