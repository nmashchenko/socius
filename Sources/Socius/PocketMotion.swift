import SwiftUI

/// The transparent native host stays fixed while the visible pocket changes size.
enum PocketMotion {
    static let size = CGSize(width: 420, height: 450)
    static let animation = Animation.spring(response: 0.27, dampingFraction: 0.88)

    static func page(forward: Bool, reduced: Bool) -> AnyTransition {
        .asymmetric(insertion: .opacity.animation(.easeOut(duration: 0.18).delay(reduced ? 0 : 0.04)),
                    removal: .opacity.animation(.easeOut(duration: 0.1)))
    }
}

struct PocketTail: Shape {
    nonisolated func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}

extension EnvironmentValues {
    @Entry var pocketQuiet = false
    @Entry var pocketAttachedOnRight = true
}
