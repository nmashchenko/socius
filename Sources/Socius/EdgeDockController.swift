import AppKit
import Observation
import QuartzCore

/// Geometry is independent of screen origin and keeps the pet's vertical position.
enum EdgeDockGeometry {
    static func dockFrame(home: CGRect, visibleScreen: CGRect) -> CGRect {
        var target = home
        let left = home.midX < visibleScreen.midX
        target.origin.x = left ? visibleScreen.minX : visibleScreen.maxX - home.width
        return target
    }
    static func restoredFrame(home: CGRect, visibleScreen: CGRect) -> CGRect {
        var target = home
        target.origin.x = min(max(home.minX, visibleScreen.minX), max(visibleScreen.minX, visibleScreen.maxX - home.width))
        target.origin.y = min(max(home.minY, visibleScreen.minY), max(visibleScreen.minY, visibleScreen.maxY - home.height))
        return target
    }
}

struct IdleSchedule {
    static let idleDelay: TimeInterval = 30
    static let peekDelay: TimeInterval = 300
    var idleSeconds: TimeInterval = 30
    var peekSeconds: TimeInterval = 300
    static let peekDuration: TimeInterval = 3
    private(set) var lastInteraction: Date
    var nextPeek: Date?
    var reminderDue: Date
    init(now: Date = Date()) {
        lastInteraction = now; reminderDue = now.addingTimeInterval(peekSeconds)
    }
    mutating func interact(at now: Date) {
        lastInteraction = now; nextPeek = nil
        reminderDue = now.addingTimeInterval(peekSeconds)
    }
    func shouldHide(at now: Date) -> Bool { now.timeIntervalSince(lastInteraction) >= idleSeconds }
    mutating func tucked(at now: Date) { nextPeek = now.addingTimeInterval(peekSeconds) }
    func shouldPeek(at now: Date) -> Bool { nextPeek.map { now >= $0 } ?? false }
    mutating func takeReminder(at now: Date) -> Bool {
        guard now >= reminderDue else { return false }
        reminderDue = now.addingTimeInterval(peekSeconds)
        return true
    }
}

@Observable final class EdgeDockController: NSObject, NSWindowDelegate {
    enum Phase { case engaged, hiding, tucked, peeking, returning }
    private(set) var phase: Phase = .engaged
    private(set) var offset: CGFloat = 0
    private(set) var reminder: String?
    private(set) var leftEdge = false
    var enabled = true { didSet { if !enabled { interact() } } }
    var idleSeconds: Double = 30 { didSet { updateTiming() } }
    var peekSeconds: Double = 300 { didSet { updateTiming() } }
    private func updateTiming() {
        schedule.idleSeconds = max(1, idleSeconds)
        schedule.peekSeconds = max(1, peekSeconds)
        schedule.interact(at: Date())
        if phase == .tucked || phase == .peeking { schedule.tucked(at: Date()) }
    }
    var menuOpen = false
    var pointerInside = false
    private let model: PetPrototype
    private weak var window: NSWindow?
    private var homeFrame = CGRect.zero
    private var schedule = IdleSchedule()
    private var watchTask: Task<Void, Never>?
    private var transitionTask: Task<Void, Never>?
    private var displayLink: CADisplayLink?
    private var travelStart = CGRect.zero
    private var travelTarget = CGRect.zero
    private var travelBegan: CFTimeInterval = 0
    private var travelCompletion: (() -> Void)?
    private var moving = false
    private var retreatAfterCare = false
    private var reaction = 0
    private var peekStarted: Date?
    private var reminderIndex = 0
    private var motionReduced: Bool { model.quiet || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    init(model: PetPrototype) { self.model = model; super.init() }
    func start(window: NSWindow) {
        self.window = window; homeFrame = window.frame; window.delegate = self
        reaction = model.reaction
        watchTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
                self?.update(at: Date())
            }
        }
    }
    func screenChanged() {
        guard let screen = screen(for: homeFrame) else { return }
        repositionHome(EdgeDockGeometry.restoredFrame(home: homeFrame, visibleScreen: screen.visibleFrame))
    }
    func stop() { watchTask?.cancel(); transitionTask?.cancel(); displayLink?.invalidate(); displayLink = nil; travelCompletion = nil }
    func hover(_ inside: Bool) {
        pointerInside = inside
        // Keep the target under the pointer until the user actually clicks it.
        if phase == .engaged { schedule.interact(at: Date()) }
    }
    func interact() {
        schedule.interact(at: Date()); reminder = nil
        guard phase != .engaged, phase != .returning else { return }
        restore()
    }
    private var careActive: Bool {
        model.shellGameActive || model.offering != nil || [.eating, .playing, .happy].contains(model.mood)
    }
    func pocketClosed() {
        guard enabled, !menuOpen, phase == .engaged else { return }
        reaction = model.reaction
        guard !careActive else { retreatAfterCare = true; schedule.interact(at: Date()); return }
        hide(at: Date())
    }
    func windowDidMove(_ notification: Notification) {
        guard !moving, let window else { return }
        if phase == .engaged { homeFrame = window.frame; schedule.interact(at: Date()) }
        else if phase == .tucked || phase == .peeking { restore() }
    }
    func repositionHome(_ frame: CGRect) {
        displayLink?.invalidate(); displayLink = nil; travelCompletion = nil
        transitionTask?.cancel(); moving = true
        window?.setFrame(frame, display: true)
        homeFrame = frame; phase = .engaged; offset = 0; reminder = nil
        moving = false; schedule.interact(at: Date())
    }
    func update(at now: Date) {
        if reaction != model.reaction { reaction = model.reaction; interact() }
        if model.shellGameActive || [.eating, .playing].contains(model.mood) { retreatAfterCare = true }
        if !enabled { retreatAfterCare = false }
        if retreatAfterCare && !careActive && enabled && !menuOpen && phase == .engaged {
            retreatAfterCare = false
            hide(at: now)
            return
        }
        let busy = menuOpen || pointerInside || careActive
        if !enabled || busy { if phase == .engaged { schedule.interact(at: now) }; return }
        switch phase {
        case .engaged: if schedule.shouldHide(at: now) { hide(at: now) }
        case .tucked:
            if model.mood != .sleeping && schedule.shouldPeek(at: now) { peek(at: now) }
        case .peeking:
            if let peekStarted, now.timeIntervalSince(peekStarted) >= IdleSchedule.peekDuration {
                phase = .tucked; offset = leftEdge ? -95 : 95; reminder = nil
            }
        case .hiding, .returning: break
        }
    }
    private func screen(for frame: CGRect) -> NSScreen? {
        NSScreen.screens.max { a, b in
            let ar = a.frame.intersection(frame), br = b.frame.intersection(frame)
            return (ar.isNull ? 0 : ar.width * ar.height) < (br.isNull ? 0 : br.width * br.height)
        }
    }
    private func hide(at now: Date) {
        guard !careActive else { return }
        guard let window, let screen = screen(for: window.frame) else { return }
        retreatAfterCare = false
        homeFrame = window.frame
        leftEdge = homeFrame.midX < screen.visibleFrame.midX
        phase = .hiding; reminder = nil
        let target = EdgeDockGeometry.dockFrame(home: homeFrame, visibleScreen: screen.visibleFrame)
        slide(to: target) { [weak self] in
            guard let self else { return }
            self.phase = .tucked; self.offset = self.leftEdge ? -95 : 95
            self.schedule.tucked(at: Date())
        }
    }
    private func peek(at now: Date) {
        phase = .peeking; peekStarted = now
        schedule.tucked(at: now)
        let showReminder = !model.quiet
        // A speaking peek emerges farther so its bubble stays legible on screen.
        offset = leftEdge ? -95 : 95
        if showReminder {
            let lines = ["Just a little hello.", "Eight arms, if you need a hand.", "I’m here. No rush."]
            reminder = model.fullness <= 20 ? "A tiny shrimp break sometime?" : lines[reminderIndex % lines.count]
            reminderIndex += 1
        }
    }
    private func restore() {
        guard let window, let screen = screen(for: homeFrame) else { return }
        phase = .returning; offset = 0; reminder = nil
        let target = EdgeDockGeometry.restoredFrame(home: homeFrame, visibleScreen: screen.visibleFrame)
        slide(to: target) { [weak self] in
            self?.phase = .engaged; self?.homeFrame = window.frame
            self?.schedule.interact(at: Date())
        }
    }
    /// Small, cancellable on-screen travel; each retarget starts at the current frame.
    private func slide(to target: CGRect, completion: @escaping @MainActor () -> Void) {
        transitionTask?.cancel()
        displayLink?.invalidate(); displayLink = nil; travelCompletion = nil
        guard let window else { return }
        moving = true
        let start = window.frame
        if motionReduced {
            window.setFrame(target, display: true); moving = false; completion(); return
        }
        travelStart = start; travelTarget = target; travelBegan = CACurrentMediaTime()
        travelCompletion = completion
        guard let screen = window.screen ?? NSScreen.main else {
            window.setFrame(target, display: true); moving = false; travelCompletion = nil; completion(); return
        }
        let link = screen.displayLink(target: self, selector: #selector(advanceTravel(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 60)
        displayLink = link
        link.add(to: .main, forMode: .common)
    }
    @objc private func advanceTravel(_ link: CADisplayLink) {
        guard let window else { link.invalidate(); displayLink = nil; travelCompletion = nil; return }
        let t = min(1, max(0, (link.targetTimestamp - travelBegan) / 0.28))
        let eased = Self.travelCurve(t)
        window.setFrameOrigin(CGPoint(x: travelStart.minX + (travelTarget.minX - travelStart.minX) * eased,
                                      y: travelStart.minY + (travelTarget.minY - travelStart.minY) * eased))
        if t >= 1 {
            link.invalidate(); displayLink = nil; moving = false
            let completion = travelCompletion; travelCompletion = nil; completion?()
        }
    }
    func simulateIdle() {
        menuOpen = false; pointerInside = false
        guard phase == .engaged else { return }
        hide(at: Date())
    }
    func simulateReminder() {
        guard phase == .tucked || phase == .peeking else { return }
        peek(at: Date())
    }
    /// Inverts the established (0.77, 0, 0.175, 1) on-screen movement curve.
    private static func travelCurve(_ x: Double) -> Double {
        var low = 0.0, high = 1.0
        for _ in 0..<16 {
            let t = (low + high) / 2
            let value = 3 * (1 - t) * (1 - t) * t * 0.77 + 3 * (1 - t) * t * t * 0.175 + t * t * t
            if value < x { low = t } else { high = t }
        }
        let t = (low + high) / 2
        return 3 * (1 - t) * t * t + t * t * t
    }
}
