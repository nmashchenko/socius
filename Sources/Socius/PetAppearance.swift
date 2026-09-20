import SwiftUI

extension NSScreen {
    /// The Dock reserves space for document windows, not the desktop pet.
    /// Keep the head below the menu bar while allowing feet at the display bottom.
    var petMovementFrame: CGRect {
        CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: visibleFrame.maxY - frame.minY)
    }
}

/// Pet colors are independent of the pocket's accessible cream-and-ink theme.
enum PetColorway: String, CaseIterable, Identifiable {
    case coral = "Coral", sage = "Sage", lavender = "Lavender", honey = "Honey"
    var id: String { rawValue }
    var body: Color {
        switch self {
        case .coral: Color(red: 0.94, green: 0.64, blue: 0.59)
        case .sage: Color(red: 0.62, green: 0.76, blue: 0.61)
        case .lavender: Color(red: 0.74, green: 0.67, blue: 0.87)
        case .honey: Color(red: 0.94, green: 0.77, blue: 0.47)
        }
    }
    var highlight: Color { body.mix(with: .white, by: 0.4) }
    var shadow: Color { body.mix(with: Palette.ink, by: 0.18) }
}

struct PetMetrics {
    var scale: CGFloat = 1
    var size: CGFloat { 140 * scale }
    var panelSize: CGSize { CGSize(width: 240 * scale, height: 270 * scale) }
    var speechHeight: CGFloat { 70 * scale }
    var footerHeight: CGFloat { 40 * scale }
    var centerFromBottom: CGFloat { 120 * scale }
    var tuckOffset: CGFloat { 95 * scale }
    // Includes the actual head, not the transparent speech area above it.
    var headFromBottom: CGFloat { centerFromBottom + size / 2 - floor(size / 24) * 5 }
    var feetFromBottom: CGFloat { centerFromBottom - size / 2 }
    static func scale(for screen: CGSize, adjustment: Double) -> CGFloat {
        let automatic = min(1.2, max(0.85, sqrt(screen.height / 900)))
        return automatic * min(1.4, max(0.75, adjustment.isFinite ? adjustment : 1))
    }
    func frame(around point: CGPoint, in screen: CGRect) -> CGRect {
        let x = min(max(point.x - panelSize.width / 2, screen.minX), screen.maxX - panelSize.width)
        let y = min(max(point.y - centerFromBottom, screen.minY - feetFromBottom), screen.maxY - headFromBottom - 4)
        return CGRect(origin: CGPoint(x: x, y: y), size: panelSize)
    }
}

struct PetAppearanceControls: View {
    @Bindable var model: PetModel
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Pet color").font(.system(size: 12, weight: .semibold))
                Spacer()
                ForEach(PetColorway.allCases) { color in
                    Button { model.colorway = color } label: {
                        Circle().fill(color.body)
                            .overlay {
                                if model.colorway == color {
                                    Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.ink)
                                }
                            }
                            .frame(width: 26, height: 26)
                            .padding(3).contentShape(Rectangle())
                    }.buttonStyle(.plain).help(color.rawValue)
                        .accessibilityLabel(color.rawValue)
                        .accessibilityAddTraits(model.colorway == color ? .isSelected : [])
                }
            }
            HStack(spacing: 12) {
                Text("Pet size").font(.system(size: 12, weight: .semibold))
                Slider(value: Binding(get: { model.sizeAdjustment }, set: { model.sizeAdjustment = ($0 * 20).rounded() / 20 }), in: 0.75...1.4)
                    .tint(Palette.green).accessibilityLabel("Pet size")
                Button("\(Int((model.sizeAdjustment * 100).rounded()))%") { model.sizeAdjustment = 1 }
                    .buttonStyle(.plain).font(.system(size: 11).monospacedDigit())
                    .frame(width: 40).help("Reset to automatic size")
            }
            Text("Adapts to each display. Adjust it to feel at home.")
                .font(.system(size: 10)).foregroundStyle(Palette.muted)
        }
    }
}
