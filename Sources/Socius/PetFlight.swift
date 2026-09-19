import Foundation

/// A quiet, interruptible flight: gradual acceleration, a shallow lift, and no bounce.
struct PetFlight {
    struct Sample {
        let position: CGPoint
        let velocity: CGPoint
        let tilt: Double
        let progress: CGFloat
        let finished: Bool
    }

    let start: CGPoint
    let target: CGPoint
    let initialVelocity: CGPoint
    let startTilt: Double
    let targetTilt: Double
    let duration: TimeInterval
    private let lift: CGFloat

    init(start: CGPoint, target: CGPoint, velocity: CGPoint = .zero, startTilt: Double = 0, targetTilt: Double = 0) {
        self.start = start; self.target = target; initialVelocity = velocity
        self.startTilt = startTilt; self.targetTilt = targetTilt
        let distance = hypot(target.x - start.x, target.y - start.y)
        // A long crossing should not whip across the screen in the same time as a short tuck.
        duration = min(0.85, 0.32 + distance / 1600)
        lift = min(8, distance / 60)
    }

    func sample(at elapsed: TimeInterval) -> Sample {
        if elapsed >= duration { return Sample(position: target, velocity: .zero, tilt: targetTilt, progress: 1, finished: true) }
        let t = max(0, elapsed / duration)
        let t2 = t * t, t3 = t2 * t, t4 = t3 * t, t5 = t4 * t
        // Quintic Hermite interpolation: zero velocity and acceleration at rest,
        // while a retarget preserves the current flight's velocity at the join.
        let progress = 6 * t5 - 15 * t4 + 10 * t3
        let speed = (30 * t4 - 60 * t3 + 30 * t2) / duration
        let carry = t - 6 * t3 + 8 * t4 - 3 * t5
        let carrySpeed = 1 - 18 * t2 + 32 * t3 - 15 * t4
        let arch = 16 * progress * progress * (1 - progress) * (1 - progress)
        let archSpeed = 32 * progress * (1 - progress) * (1 - 2 * progress) * speed
        let dx = target.x - start.x, dy = target.y - start.y
        return Sample(
            position: CGPoint(x: start.x + dx * progress + initialVelocity.x * duration * carry,
                              y: start.y + dy * progress + initialVelocity.y * duration * carry + lift * arch),
            velocity: CGPoint(x: dx * speed + initialVelocity.x * carrySpeed,
                              y: dy * speed + initialVelocity.y * carrySpeed + lift * archSpeed),
            tilt: startTilt + (targetTilt - startTilt) * progress + (dx == 0 ? 0 : dx < 0 ? -2 : 2) * arch,
            progress: progress,
            finished: false)
    }
}
