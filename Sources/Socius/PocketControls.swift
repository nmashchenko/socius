import SwiftUI
import CyclopTools

typealias PocketMetrics = CyclopTools.PocketMetrics

struct PocketInputStyle: ViewModifier {
    func body(content: Content) -> some View {
        content.textFieldStyle(.plain).font(.system(size: 12))
            .padding(.horizontal, PocketMetrics.controlInset)
            .frame(height: PocketMetrics.controlHeight)
            .background(Palette.green.opacity(0.08), in: RoundedRectangle(cornerRadius: PocketMetrics.cornerRadius))
    }
}


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

struct PocketToggleStyle: ToggleStyle {
    var showsLabel = true
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: 8) {
                Capsule().fill(configuration.isOn ? Palette.green : Palette.muted.opacity(0.25))
                    .frame(width: 30, height: 18)
                    .overlay(Circle().fill(Palette.cream).frame(width: 12, height: 12).offset(x: configuration.isOn ? 6 : -6))
                if showsLabel { configuration.label.font(.system(size: 11, weight: .medium)) }
            }
        }.buttonStyle(.plain).accessibilityValue(configuration.isOn ? "On" : "Off")
    }
}
