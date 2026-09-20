import SwiftUI

/// All pet artwork uses the same integer pixel grid, including food and toys.
struct PixelProp: View {
    enum Kind { case shrimp, shell, heart, pearl }
    var kind: Kind
    var bite = 0
    var body: some View {
        Canvas { context, size in
            let rows: [String] = switch kind {
            case .shrimp: ["  rrrr   ", " rrwrrr  ", "rrw  rkr ", "rrw   rr ", " rrr     ", "  rrrr   ", "   rr rr ", "   r   r "]
            case .shell: ["   yy    ", "  ybyy   ", " ybybyy  ", "ybybybyy ", "ybybybyy ", " yyyyyy  ", "  yyyy   "]
            case .pearl: ["        ", "  www   ", " wwyww  ", " wwwww  ", " wwwyw  ", "  www   "]
            case .heart: [" rr rr ", "rrrrrrr", "rrrrrrr", " rrrrr ", "  rrr  ", "   r   "]
            }
            let unit = floor(min(size.width / 9, size.height / 8))
            // Shell artwork occupies 8 × 7 pixels inside the shared 9 × 8 grid.
            // Center the visible sprite, not the grid's trailing empty space.
            let origin = kind == .shell
                ? CGPoint(x: floor((size.width - 8 * unit) / 2), y: floor((size.height - 7 * unit) / 2))
                : .zero
            for (y, row) in rows.enumerated() { for (x, pixel) in row.enumerated() where pixel != " " {
                if kind == .shrimp && bite > 0 && x > 4 && y < 3 + bite { continue }
                let color: Color = switch pixel {
                case "k": Palette.ink
                case "g": Palette.green
                case "w", "y": Palette.cream
                case "b": Color(red: 0.56, green: 0.66, blue: 0.76)
                default: Color(red: 0.88, green: 0.40, blue: 0.42)
                }
                context.fill(Path(CGRect(x: origin.x + CGFloat(x) * unit, y: origin.y + CGFloat(y) * unit, width: unit, height: unit)), with: .color(color), style: FillStyle(antialiased: false))
            } }
        }.accessibilityHidden(true)
    }
}

struct CreatureView: View {
    let model: PetModel
    var size: CGFloat = 150
    var idleMotion = true
    var shyEdge: Bool? = nil
    var walking = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase = 0
    private var still: Bool { reduceMotion || model.quiet }
    private var stepping: Bool { walking && !still }
    private var rippling: Bool { idleMotion && !still && !model.shellGameActive && [.content, .hungry, .grumpy].contains(model.mood) }
    private var breathing: Bool { !still && model.mood == .sleeping }
    private var waving: Bool { shyEdge != nil && !still && [.content, .hungry, .grumpy].contains(model.mood) }
    private var chewing: Bool { model.mood == .eating && (3...7).contains(phase) }
    var body: some View {
        ZStack {
            TimelineView(.animation(minimumInterval: stepping ? 1.0 / 30 : 0.25, paused: !stepping && !rippling && !breathing && !waving)) { timeline in
                let time = timeline.date.timeIntervalSinceReferenceDate
                sprite(at: time)
                    .offset(y: stepping ? -abs(sin(time * 12)) * 3 : 0)
                    .rotationEffect(.degrees(stepping ? sin(time * 12) * 2 : 0))
                    .scaleEffect(x: model.mood == .sleeping ? 1.03 : chewing && !still && phase % 2 == 0 ? 1.04 : 1,
                                 y: model.mood == .sleeping ? 0.87 + (breathing ? sin(time * 1.25) * 0.018 : 0) : chewing && !still && phase % 2 == 0 ? 0.96 : 1, anchor: .bottom)
                    .overlay(alignment: .topTrailing) {
                        if model.mood == .sleeping {
                            sleepBubbles(time: time).frame(width: 28, height: 40).offset(x: -4, y: 8)
                        }
                    }
            }
                .offset(y: model.mood == .happy && !still && phase == 1 ? -3 : 0)
                
                .animation(still ? nil : .spring(duration: 0.5, bounce: 0.2), value: model.mood)
                .animation(still ? nil : .easeInOut(duration: 0.15), value: phase)
            if model.mood == .eating && phase < 8 {
                PixelProp(kind: .shrimp, bite: max(0, (phase - 3) / 2))
                    .frame(width: size * 0.28, height: size * 0.26)
                    .offset(x: still ? 0 : max(0, CGFloat(3 - phase)) * -size * 0.12, y: size * 0.14)
                    .animation(still ? nil : .easeOut(duration: 0.2), value: phase)
            }
            if model.mood == .playing {
                PixelProp(kind: .pearl).frame(width: size * 0.25, height: size * 0.25)
                    .offset(y: size * 0.3)
            }
            if model.mood == .happy || model.mood == .eating && phase >= 8 {
                heartTrail
            }
        }
        .frame(width: size, height: size)
        .task(id: model.reaction) {
            phase = 0
            guard [.eating, .playing, .happy].contains(model.mood) else { return }
            for step in 1...(model.mood == .happy ? 4 : 10) {
                do { try await Task.sleep(for: .milliseconds(model.mood == .happy ? 140 : 230)) } catch { return }
                phase = step
            }
        }
        .accessibilityLabel("\(model.displayName), \(model.mood.rawValue.lowercased())")
    }
    private var heartTrail: some View {
        ForEach(0..<3) { index in
            let x = size * (0.17 + CGFloat(index) * 0.13)
            let rise: CGFloat = still ? 0 : CGFloat(max(0, phase - index)) * 4
            let y = -size * (0.16 + CGFloat(index) * 0.11) - rise
            let visible = still || model.mood != .happy || (phase >= index && phase < index + 3)
            PixelProp(kind: .heart).frame(width: size * 0.15, height: size * 0.15)
                .offset(x: x, y: y)
                .opacity(visible ? 1 : 0)
                .animation(.easeOut(duration: 0.12), value: phase)
        }
    }
    private func sleepBubbles(time: TimeInterval) -> some View {
        Canvas { context, _ in
            for index in 0..<3 {
                let progress = still ? Double(index) / 3 : (time / 4.5 + Double(index) / 3).truncatingRemainder(dividingBy: 1)
                let width = 3 + progress * 3
                let rect = CGRect(x: 3 + progress * 12, y: 34 - progress * 32, width: width, height: width)
                context.stroke(Path(ellipseIn: rect), with: .color(Palette.peach.opacity(still ? 0.6 : (1 - progress) * 0.75)), lineWidth: 1)
            }
        }.accessibilityHidden(true)
    }
    private func sprite(at time: TimeInterval) -> some View {
        Canvas { context, frame in
            let unit = floor(frame.width / 24)
            let inset = (frame.width - unit * 24) / 2
            let coral = model.mood == .sleeping ? Color(red: 0.89, green: 0.70, blue: 0.69) : model.mood == .hungry ? Color(red: 0.82, green: 0.66, blue: 0.64) : Color(red: 0.94, green: 0.64, blue: 0.59)
            func block(_ x: Int, _ y: Int, _ w: Int = 1, _ h: Int = 1, _ color: Color) {
                context.fill(Path(CGRect(x: inset + CGFloat(x) * unit, y: CGFloat(y) * unit, width: CGFloat(w) * unit, height: CGFloat(h) * unit)), with: .color(color), style: FillStyle(antialiased: false))
            }
            // Round head, small curled tentacles, ample forehead: relaxed baby proportions.
            for (y, bounds) in [(5, 9...14), (6, 7...16), (7, 5...18), (8, 4...19)] {
                block(bounds.lowerBound, y, bounds.count, 1, coral)
            }
            block(4, 9, 16, 8, coral)
            block(4, 17, 16, 1, coral)
            if model.mood == .sleeping {
                // Arms gather under the mantle into a soft, self-contained curl.
                block(5, 18, 14, 2, coral)
                block(6, 20, 12, 1, coral)
                let curl = Color(red: 0.85, green: 0.53, blue: 0.52)
                for x in [6, 10, 14] {
                    block(x, 18, 1, 2, curl)
                    block(x + 1, 19, 2, 1, curl)
                }
                block(3, 16, 2, 3, coral); block(19, 16, 2, 3, coral)
            } else {
                for (index, x) in [4, 7, 10, 13, 16, 19].enumerated() {
                    let wave = stepping ? Int((sin(time * 12 + Double(index % 2) * .pi) * 1.5).rounded())
                        : rippling ? Int((sin(time * 1.8 - Double(index) * 0.9) * 1.1).rounded()) : 0
                    let length = (x % 2 == 0 ? 3 : 4) + wave
                    block(x, 18, 2, length, coral)
                    block(x + (x < 12 ? 1 : -1), 18 + length, 2, 1, coral)
                }
                let lift = rippling ? Int((sin(time * 1.8) * 1.1).rounded()) : 0
                let waveTime = time.truncatingRemainder(dividingBy: 12)
                let hello = waving && waveTime < 2 ? Int((abs(sin(waveTime * .pi)) * 4).rounded()) : 0
                let leftHello = shyEdge == false ? hello : 0
                let rightHello = shyEdge == true ? hello : 0
                block(2, 16 + lift - leftHello, 2, 3 + leftHello, coral)
                block(20, 16 - lift - rightHello, 2, 3 + rightHello, coral)
                block(2, 19 + lift, 2, 1, coral); block(20, 19 - lift, 2, 1, coral)
            }
            block(7, 8, 3, 1, Color(red: 1, green: 0.79, blue: 0.73))
            block(6, 9, 2, 1, Color(red: 1, green: 0.79, blue: 0.73))
            let eyesClosed = [.sleeping, .happy, .grumpy].contains(model.mood) || chewing
            let faceShift = shyEdge.map { $0 ? 2 : -2 } ?? 0
            for x in [7 + faceShift, 15 + faceShift] {
                if eyesClosed {
                    block(x, 12, 2, 1, Palette.ink)
                    if model.mood != .sleeping { block(x - 1, 13, 1, 1, Palette.ink); block(x + 2, 13, 1, 1, Palette.ink) }
                } else {
                    block(x, 11, 2, 3, Palette.ink)
                    block(x, 11, 1, 1, Palette.cream)
                }
            }
            let blush = Color(red: 0.97, green: 0.49, blue: 0.49).opacity(model.mood == .happy ? 0.85 : 0.55)
            block(5, 14, 3, 1, blush); block(16, 14, 3, 1, blush)
            if chewing && phase % 2 == 0 {
                block(11, 15, 2, 2, Palette.ink)
            } else if !model.toolsAvailable || model.mood == .grumpy {
                block(11, 15, 2, 1, Palette.ink)
                block(10, 16, 1, 1, Palette.ink); block(13, 16, 1, 1, Palette.ink)
            } else {
                block(10, 15, 1, 1, Palette.ink); block(13, 15, 1, 1, Palette.ink)
                block(11, 16, 2, 1, Palette.ink)
            }
        }
    }
}
