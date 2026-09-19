import SwiftUI

struct PocketButtonStyle: ButtonStyle {
    var prominent = false
    var compact = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 11 : 12, weight: .semibold, design: .rounded))
            .lineLimit(1)
            .padding(.horizontal, compact ? 9 : 13).padding(.vertical, compact ? 7 : 10)
            .foregroundStyle(prominent ? Palette.cream : Palette.ink)
            .background(prominent ? Palette.green : Palette.green.opacity(configuration.isPressed ? 0.18 : 0.09), in: RoundedRectangle(cornerRadius: 10))
            .opacity(enabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
            .contentShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct PocketSearchField: View {
    let placeholder: String
    @Binding var text: String
    @FocusState private var focused: Bool
    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass").font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.muted)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain).font(.system(size: 12)).focused($focused)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.muted) }
                    .buttonStyle(.plain).accessibilityLabel("Clear search")
            }
        }.padding(.horizontal, 12).frame(height: 36)
            .background(.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Palette.green.opacity(focused ? 0.55 : 0.12), lineWidth: 1))
    }
}

struct PocketToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: 8) {
                Capsule().fill(configuration.isOn ? Palette.green : Palette.muted.opacity(0.25))
                    .frame(width: 30, height: 18)
                    .overlay(Circle().fill(Palette.cream).frame(width: 12, height: 12).offset(x: configuration.isOn ? 6 : -6))
                configuration.label.font(.system(size: 11, weight: .medium))
            }
        }.buttonStyle(.plain).accessibilityValue(configuration.isOn ? "On" : "Off")
    }
}
