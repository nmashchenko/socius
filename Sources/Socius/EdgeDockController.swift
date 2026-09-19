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
    /// Follow the visible flight with the window until its edge reaches the screen.
    /// Only the remaining off-screen distance belongs in the clipped content offset.
    static func placement(visualOrigin: CGPoint, windowSize: CGSize, visibleScreen: CGRect) -> (frame: CGRect, offset: CGFloat) {
        let x = min(max(visualOrigin.x, visibleScreen.minX), max(visibleScreen.minX, visibleScreen.maxX - windowSize.width))
        return (CGRect(origin: CGPoint(x: x, y: visualOrigin.y), size: windowSize), visualOrigin.x - x)
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
    private(set) var tilt: Double = 0
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
    private let model: PetModel
    private weak var window: NSWindow?
    private var homeFrame = CGRect.zero
    private var schedule = IdleSchedule()
    private var watchTask: Task<Void, Never>?
    private var displayLink: CADisplayLink?
    private var flight: PetFlight?
    private var travelVelocity = CGPoint.zero
    private var travelBegan: CFTimeInterval = 0
    private var travelCompletion: (() -> Void)?
    private var moving = false
    private(set) var dragging = false
    private var dragOrigin = CGPoint.zero
    private var dragPointerOrigin = CGPoint.zero
    private(set) var pointerPressed = false
    private var travelScreen = CGRect.zero
    private var retreatAfterCare = false
    private var reaction = 0
    private var peekStarted: Date?
    private var reminderIndex = 0
    private var motionReduced: Bool { model.quiet || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    private var tuckedTilt: Double { motionReduced ? 0 : leftEdge ? 4 : -4 }

    init(model: PetModel) { self.model = model; super.init() }
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
    private func cancelTravel() {
        displayLink?.invalidate(); displayLink = nil; travelCompletion = nil
        flight = nil; travelVelocity = .zero
        moving = false
    }
    func stop() { watchTask?.cancel(); cancelTravel() }
    func hover(_ inside: Bool) {
        pointerInside = inside
        // Keep the target under the pointer until the user actually clicks it.
        if phase == .engaged { schedule.interact(at: Date()) }
    }
    func interact() {
        schedule.interact(at: Date()); reminder = nil
        guard !pointerPressed, !dragging, phase != .engaged else { return }
        guard phase != .returning || displayLink == nil else { return }
        restore()
    }
    private var careActive: Bool {
        model.shellGameActive || model.offering != nil || [.eating, .playing, .happy].contains(model.mood)
    }
    func pocketClosed() {
        guard enabled, !menuOpen, !pointerPressed, !dragging, phase == .engaged else { return }
        reaction = model.reaction
        guard !careActive else { retreatAfterCare = true; schedule.interact(at: Date()); return }
        hide(at: Date())
    }
    func pressPet() {
        pointerPressed = true
        // Freeze travel on mouse-down, before deciding between a click and a drag.
        cancelTravel()
        schedule.interact(at: Date())
    }
    func releasePet() {
        pointerPressed = false
        schedule.interact(at: Date())
    }
    func beginUserDrag(at point: CGPoint) {
        guard !dragging, let window else { return }
        cancelTravel()
        dragging = true; retreatAfterCare = false; reminder = nil
        // Fold the content's screen position into the window exactly once.
        let origin = CGPoint(x: window.frame.minX + offset, y: window.frame.minY)
        moving = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            context.allowsImplicitAnimation = false
            offset = 0; tilt = 0; phase = .engaged
            // Resolve the current SwiftUI drawing before moving its backing surface.
            window.contentView?.needsLayout = true
            window.contentView?.layoutSubtreeIfNeeded()
            window.contentView?.displayIfNeeded()
            window.setFrameOrigin(origin)
        }
        dragOrigin = window.frame.origin; dragPointerOrigin = point
        moving = false
        schedule.interact(at: Date())
    }
    func dragPet(to point: CGPoint) {
        guard dragging else { return }
        moving = true
        window?.setFrameOrigin(CGPoint(x: dragOrigin.x + point.x - dragPointerOrigin.x,
                                      y: dragOrigin.y + point.y - dragPointerOrigin.y))
        moving = false
    }
    func endUserDrag() {
        guard dragging, let window else { return }
        dragging = false
        homeFrame = window.frame
        phase = .engaged; offset = 0; tilt = 0; retreatAfterCare = false
        schedule.interact(at: Date())
    }
    func windowDidMove(_ notification: Notification) {
        guard !moving, !pointerPressed, !dragging, phase == .engaged, let window else { return }

        homeFrame = window.frame
        schedule.interact(at: Date())
    }
    func repositionHome(_ frame: CGRect) {
        (window as? PetPanel)?.petInput?.cancel()
        dragging = false; pointerPressed = false; retreatAfterCare = false
        cancelTravel(); moving = true
        window?.setFrame(frame, display: true)
        homeFrame = frame; phase = .engaged; offset = 0; tilt = 0; reminder = nil
        moving = false; schedule.interact(at: Date())
    }
    func update(at now: Date) {
        if pointerPressed || dragging {
            schedule.interact(at: now)
            return
        }
        if NSEvent.pressedMouseButtons & 1 != 0 { schedule.interact(at: now); return }
        if reaction != model.reaction { reaction = model.reaction; interact() }
        if model.shellGameActive || model.offering != nil || [.eating, .playing].contains(model.mood) { retreatAfterCare = true }
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
                phase = .tucked; offset = leftEdge ? -95 : 95; tilt = tuckedTilt; reminder = nil
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
        guard !careActive, !pointerPressed, !dragging else { return }
        guard let window, let screen = screen(for: window.frame) else { return }
        retreatAfterCare = false
        homeFrame = window.frame
        leftEdge = homeFrame.midX < screen.visibleFrame.midX
        phase = .hiding; reminder = nil
        let target = EdgeDockGeometry.dockFrame(home: homeFrame, visibleScreen: screen.visibleFrame)
        slide(to: target, targetOffset: leftEdge ? -95 : 95, targetTilt: tuckedTilt) { [weak self] in
            guard let self else { return }
            self.phase = .tucked
            self.schedule.tucked(at: Date())
        }
    }
    private func peek(at now: Date) {
        phase = .peeking; peekStarted = now
        schedule.tucked(at: now)
        let showReminder = !model.quiet
        offset = leftEdge ? -95 : 95
        if showReminder {
            let lines = ["Just a little hello.", "Eight arms, if you need a hand.", "I’m here. No rush."]
            reminder = model.fullness <= 20 ? "A tiny shrimp break sometime?" : lines[reminderIndex % lines.count]
            reminderIndex += 1
        }
    }
    private func restore() {
        guard let window, let screen = screen(for: homeFrame) else { return }
        phase = .returning; reminder = nil
        let target = EdgeDockGeometry.restoredFrame(home: homeFrame, visibleScreen: screen.visibleFrame)
        slide(to: target) { [weak self] in
            self?.phase = .engaged; self?.homeFrame = window.frame
            self?.schedule.interact(at: Date())
        }
    }
    /// Small, cancellable on-screen travel; each retarget starts at the current frame.
    private func slide(to target: CGRect, targetOffset: CGFloat = 0, targetTilt: Double = 0, completion: @escaping @MainActor () -> Void) {
        let velocity = travelVelocity
        cancelTravel()
        guard let window else { return }
        moving = true
        if motionReduced {
            window.setFrame(target, display: true); offset = targetOffset; tilt = 0; moving = false; completion(); return
        }
        // Plan the visible pet's position; window travel and content offset use the same sample.
        flight = PetFlight(start: CGPoint(x: window.frame.minX + offset, y: window.frame.minY),
                           target: CGPoint(x: target.minX + targetOffset, y: target.minY),
                           velocity: velocity, startTilt: tilt, targetTilt: targetTilt)
        travelBegan = CACurrentMediaTime()
        travelCompletion = completion
        guard let screen = window.screen ?? NSScreen.main else {
            window.setFrame(target, display: true); offset = targetOffset; tilt = targetTilt; moving = false; travelCompletion = nil; flight = nil; completion(); return
        }
        travelScreen = screen.visibleFrame
        let link = screen.displayLink(target: self, selector: #selector(advanceTravel(_:)))
        let refreshRate = Float(screen.maximumFramesPerSecond)
        link.preferredFrameRateRange = CAFrameRateRange(minimum: min(60, refreshRate), maximum: refreshRate, preferred: refreshRate)
        displayLink = link
        link.add(to: .main, forMode: .common)
    }
    @objc private func advanceTravel(_ link: CADisplayLink) {
        guard let window, let flight else { cancelTravel(); return }
        let sample = flight.sample(at: link.targetTimestamp - travelBegan)
        travelVelocity = sample.velocity; tilt = sample.tilt
        let placement = EdgeDockGeometry.placement(visualOrigin: sample.position, windowSize: window.frame.size, visibleScreen: travelScreen)
        offset = placement.offset
        window.setFrameOrigin(placement.frame.origin)
        if sample.finished {
            let completion = travelCompletion
            cancelTravel()
            completion?()
        }
    }
    /// Launch at the edge without flashing the engaged pet first.
    func beginIdle() {
        guard let window, let screen = screen(for: window.frame) else { return }
        cancelTravel()
        homeFrame = window.frame
        leftEdge = homeFrame.midX < screen.visibleFrame.midX
        moving = true
        window.setFrame(EdgeDockGeometry.dockFrame(home: homeFrame, visibleScreen: screen.visibleFrame), display: true)
        moving = false
        phase = .tucked; offset = leftEdge ? -95 : 95; tilt = tuckedTilt; reminder = nil
        schedule.tucked(at: Date())
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
}
