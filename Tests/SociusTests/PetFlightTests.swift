import Foundation
import Testing
@testable import Socius

@MainActor @Suite struct PetFlightTests {
    @Test(arguments: [-1000.0, -120, 120, 1000])
    func flightStartsAndLandsGentlyWithoutOvershoot(distance: Double) {
        let flight = PetFlight(start: CGPoint(x: 50, y: 80), target: CGPoint(x: 50 + distance, y: 80))
        let start = flight.sample(at: 0)
        let end = flight.sample(at: flight.duration)
        #expect(start.position == flight.start)
        #expect(start.velocity == .zero)
        #expect(end.position == flight.target)
        #expect(end.velocity == .zero)
        #expect(end.tilt == 0)
        let lower = min(flight.start.x, flight.target.x), upper = max(flight.start.x, flight.target.x)
        var previous = start.position
        for frame in 1...Int(ceil(flight.duration * 60)) {
            let sample = flight.sample(at: Double(frame) / 60)
            #expect(sample.position.x >= lower && sample.position.x <= upper)
            #expect(sample.position.y >= 80 && sample.position.y <= 88)
            #expect(abs(sample.position.x - previous.x) < 40) // no large 60 Hz jumps across a 1,000-point trip
            previous = sample.position
        }
        #expect(abs(flight.sample(at: 1.0 / 60).position.x - start.position.x) < 0.4)
        #expect(abs(flight.sample(at: flight.duration - 1.0 / 60).position.x - end.position.x) < 0.4)
    }

    @Test func longTripsHaveMoreTimeThanShortTucks() {
        let short = PetFlight(start: .zero, target: CGPoint(x: 95, y: 0))
        let long = PetFlight(start: .zero, target: CGPoint(x: 800, y: 0))
        #expect(short.duration >= 0.35 && short.duration < 0.45)
        #expect(long.duration >= 0.7 && long.duration <= 0.85)
    }

    @Test func reversingInFlightPreservesPositionAndVelocity() {
        let outbound = PetFlight(start: .zero, target: CGPoint(x: 500, y: 0), targetTilt: -4)
        let handoff = outbound.sample(at: outbound.duration * 0.35)
        let inbound = PetFlight(start: handoff.position, target: .zero, velocity: handoff.velocity, startTilt: handoff.tilt)
        let resumed = inbound.sample(at: 0)
        #expect(resumed.position == handoff.position)
        #expect(resumed.velocity == handoff.velocity)
        #expect(resumed.tilt == handoff.tilt)
        #expect(inbound.sample(at: inbound.duration).position == .zero)
        #expect(inbound.sample(at: inbound.duration).tilt == 0)
    }
}
