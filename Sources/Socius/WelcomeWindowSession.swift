import AppKit

/// A visible introduction has one exit: complete it intentionally, or cancel it
/// when its window closes. Focus changes never finish or hide the introduction.
final class WelcomeWindowSession: NSObject, NSWindowDelegate {
    private weak var window: NSWindow?
    private var finished = false
    private let didFinish: (Bool) -> Void

    init(window: NSWindow, didFinish: @escaping (Bool) -> Void) {
        self.window = window
        self.didFinish = didFinish
        super.init()
        if let panel = window as? NSPanel { panel.hidesOnDeactivate = false }
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenPrimary]
        window.delegate = self
    }
    func complete() { finish(completed: true) }
    func cancel() { finish(completed: false) }
    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow, closing === window else { return }
        finish(completed: false)
    }
    private func finish(completed: Bool) {
        guard !finished else { return }
        finished = true
        didFinish(completed)
    }
}
