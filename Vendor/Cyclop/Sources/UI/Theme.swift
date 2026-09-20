import SwiftUI

/// Shared layout scale for Socius and its imported pocket panes.
public enum PocketMetrics {
    public static let inputFill = Color(red: 0.37, green: 0.47, blue: 0.31).opacity(0.08)
    public static let small: CGFloat = 6
    public static let rowGap: CGFloat = 8
    public static let controlInset: CGFloat = 12
    public static let sectionGap: CGFloat = 16
    public static let pageInset: CGFloat = 18
    public static let controlHeight: CGFloat = 34
    public static let rowHeight: CGFloat = 30
    public static let cornerRadius: CGFloat = 10
}

enum Theme {
    static let ink = Color(red: 0.23, green: 0.28, blue: 0.24)
    static let openAnimation = Animation.spring(response: 0.27, dampingFraction: 0.82)
    static let contentAnimation = Animation.easeOut(duration: 0.16)
    /// Pane switching: the outgoing pane leaves faster than the incoming one
    /// arrives, so the two are never both half-visible for long.
    static let paneAnimation = Animation.easeOut(duration: 0.18)
    static let paneIn = Animation.easeOut(duration: 0.20).delay(0.04)
    static let paneOut = Animation.easeIn(duration: 0.12)
    static let artworkAnimation = Animation.easeOut(duration: 0.28)

    static let collapsedTopRadius: CGFloat = 6
    static let collapsedBottomRadius: CGFloat = 9
    static let openTopRadius: CGFloat = 12
    static let openBottomRadius: CGFloat = 22

    static let secondary = Theme.ink.opacity(0.78)
    static let tertiary = Theme.ink.opacity(0.62)
    static let surface = Theme.ink.opacity(0.08)
    static let surfaceHover = Theme.ink.opacity(0.14)
    static let hairline = Theme.ink.opacity(0.10)
}

/// Flat, focus-free button used for every control in the panel.
struct NotchButtonStyle: ButtonStyle {
    var size: CGFloat = 26
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: prominent ? 17 : 13, weight: .medium))
            .foregroundStyle(Theme.ink)
            .frame(width: size, height: size)
            .background(
                Circle().fill(prominent ? Theme.surfaceHover : Color.clear)
            )
            .opacity(configuration.isPressed ? 0.55 : 1)
            .contentShape(Circle())
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension View {
    /// Tracks hover without triggering layout changes in the parent.
    func onHoverChange(_ action: @escaping (Bool) -> Void) -> some View {
        onHover(perform: action)
    }
}

/// Drawn rather than `NSSwitch`-backed: the panel is a non-activating window
/// that almost never becomes key (that is what keeps hovering it from
/// stealing focus from whatever app was in front), and `NSSwitch` renders its
/// on-state in gray rather than accent blue whenever its window is not key.
/// A plain `Color` fill has no such state to lose.
struct NotchToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            Capsule()
                .fill(configuration.isOn ? Color(red: 0.37, green: 0.47, blue: 0.31) : Theme.surfaceHover)
                .frame(width: 28, height: 16)
                .overlay(
                    Circle()
                        .fill(.white)
                        .frame(width: 12, height: 12)
                        .offset(x: configuration.isOn ? 6 : -6)
                )
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: configuration.isOn)
    }
}

func formatTime(_ seconds: TimeInterval) -> String {
    guard seconds.isFinite, seconds >= 0 else { return "--:--" }
    let total = Int(seconds.rounded())
    return String(format: "%d:%02d", total / 60, total % 60)
}
