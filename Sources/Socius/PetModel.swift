import SwiftUI
import Observation

@Observable final class PetModel {
    enum Mood: String, CaseIterable {
        case content = "Feeling good", happy = "Happy", eating = "Snacking", playing = "Playing", sleeping = "Sleeping", hungry = "Hungry", grumpy = "Grumpy"
    }
    var mood: Mood = .content
    var speech = "Hi, I’m Mochi. A little company for your desktop."
    var panelOpen = false
    var onboardingActive = false
    var desktopSuppressed = false
    var selectedTool = "Shelf"
    var reaction = 0
    enum Offering: String { case snack, shell, rest }
    var offering: Offering?
    func offer(_ item: Offering) {
        offering = offering == item ? nil : item
        speech = offering == nil ? "All eight arms, ready to help." : item == .snack ? "A little shrimp for me?" : item == .shell ? "Find my pearl?" : "Time for a quiet curl?"
    }
    func acceptOffering() {
        guard let item = offering else { pet(); return }
        offering = nil
        switch item { case .snack: feed(); case .shell: startShellGame(); case .rest: if mood != .sleeping { sleep() } }
    }
    func receive(_ value: String) -> Bool {
        guard let item = Offering(rawValue: value) else { return false }
        offering = item; acceptOffering(); return true
    }
    // Species-specific choices live together, ready for future animals.
    enum Species {
        case octopus
        var foodName: String { switch self { case .octopus: "Shrimp" } }
        var gameName: String { switch self { case .octopus: "Shell hunt" } }
    }
    let species: Species = .octopus
    var shellGameActive = false
    var emptyShells: Set<Int> = []
    private(set) var pearlShell = 1
    func startShellGame(prize: Int? = nil) {
        resetTask?.cancel(); offering = nil
        shellGameActive = true; emptyShells = []
        pearlShell = prize.map { min(2, max(0, $0)) } ?? Int.random(in: 0...2)
        mood = .content; speech = "I hid a pearl. Pick a shell!"; reaction += 1
    }
    func chooseShell(_ index: Int) {
        guard shellGameActive, (0...2).contains(index), !emptyShells.contains(index) else { return }
        if index == pearlShell {
            shellGameActive = false; play()
        } else {
            emptyShells.insert(index); speech = "Just sand! Try another shell."
        }
    }
    private let preferences: UserDefaults?
    var name = "Mochi" { didSet { preferences?.set(name, forKey: "petName") } }
    var displayName: String { name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Mochi" : name.trimmingCharacters(in: .whitespacesAndNewlines) }
    @ObservationIgnored var shortcutChanged: (() -> Void)?
    var shortcutError: String?
    var recordingShortcut = false
    var shortcut = PetShortcut() { didSet {
        shortcutChanged?()
        guard shortcutError == nil else { return }
        if let data = try? JSONEncoder().encode(shortcut) { preferences?.set(data, forKey: "petShortcut") }
    } }
    func setShortcut(_ proposed: PetShortcut) {
        let previous = shortcut
        shortcut = proposed
        if let error = shortcutError {
            shortcut = previous
            shortcutError = error
        }
    }
    var hiddenTools: Set<String> = [] { didSet { preferences?.set(Array(hiddenTools).sorted(), forKey: "hiddenTools") } }
    func showsTool(_ tool: String) -> Bool { tool == "Settings" || !hiddenTools.contains(tool) }
    var colorway: PetColorway = .coral { didSet { preferences?.set(colorway.rawValue, forKey: "petColorway") } }
    var sizeAdjustment = 1.0 { didSet {
        preferences?.set(sizeAdjustment, forKey: "petSizeAdjustment")
        appearanceChanged?()
    } }
    @ObservationIgnored var appearanceChanged: (() -> Void)?
    var desktopScale: CGFloat = 1
    var metrics: PetMetrics { PetMetrics(scale: desktopScale) }
    init(preferences: UserDefaults? = nil) {
        self.preferences = preferences
        name = preferences?.string(forKey: "petName") ?? "Mochi"
        colorway = preferences?.string(forKey: "petColorway").flatMap(PetColorway.init(rawValue:)) ?? .coral
        let savedSize = preferences?.object(forKey: "petSizeAdjustment") as? Double ?? 1
        sizeAdjustment = savedSize.isFinite ? min(1.4, max(0.75, savedSize)) : 1
        preferences?.removeObject(forKey: "quietMode")
        hiddenTools = Set(preferences?.stringArray(forKey: "hiddenTools") ?? [])
        if let data = preferences?.data(forKey: "petShortcut"), let saved = try? JSONDecoder().decode(PetShortcut.self, from: data) { shortcut = saved }
        speech = "Hi, I’m \(displayName). A little company for your desktop."
    }
    var fullness = 75.0
    var happiness = 80.0
    var toolsAvailable: Bool { fullness > 20 && happiness > 20 }
    var careHP: Double { min(fullness, happiness) }
    var moodLabel: String { toolsAvailable ? mood.rawValue : restingMood.rawValue }
    var restingMood: Mood { fullness <= 20 ? .hungry : happiness <= 20 ? .grumpy : .content }
    private var restingSpeech: String {
        toolsAvailable ? "All eight arms, ready to help." : fullness <= 20 ? "Still peckish. Got another snack?" : "A little more playtime?"
    }
    func tick() {
        guard mood != .sleeping else { return }
        fullness = max(0, fullness - 100.0 / (12 * 60))
        happiness = max(0, happiness - 100.0 / (18 * 60))
        if [.content, .hungry, .grumpy].contains(mood), !shellGameActive, offering == nil {
            if mood != restingMood { speech = restingSpeech }
            mood = restingMood
        }
        if !toolsAvailable { panelOpen = false }
    }
    func preview(_ state: Mood) {
        resetTask?.cancel(); shellGameActive = false; offering = nil; panelOpen = false
        fullness = state == .hungry ? 12 : 75
        happiness = state == .grumpy ? 12 : 80
        mood = state
        speech = state == .hungry ? "Eight arms. Zero snacks. Help?" : state == .grumpy ? "Not in the mood. Play with me first?" : "All eight arms, ready to help."
    }
    func openPocket() {
        guard toolsAvailable else {
            speech = fullness <= 20 ? "Snack first. Shortcuts second." : "A little playtime, then I’m all yours."
            reaction += 1; return
        }
        panelOpen.toggle()
    }
    private var resetTask: Task<Void, Never>?

    func cancelActivity() {
        resetTask?.cancel()
        offering = nil; shellGameActive = false; panelOpen = false
        mood = restingMood
        speech = restingSpeech
    }
    func react(_ mood: Mood, _ message: String) {
        resetTask?.cancel()
        offering = nil; shellGameActive = false
        self.mood = mood; speech = message; reaction += 1
        if mood != .sleeping {
            resetTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(mood == .happy ? 650 : 2600))
                guard !Task.isCancelled else { return }
                guard let self else { return }
                self.mood = self.restingMood
                self.speech = self.restingSpeech
            }
        }
    }
    func pet() { happiness = min(100, happiness + 2); react(.happy, ["Oh! That’s the spot.", "You’re my favorite coworker.", "A tiny high five for you."][reaction % 3]) }
    func feed() { fullness = min(100, fullness + 45); react(.eating, "My favorite. Little shrimp, big happiness.") }
    func play() { happiness = min(100, happiness + 45); react(.playing, "You found my pearl! Again sometime?") }
    func sleep() {
        if mood == .sleeping { react(.happy, "Good morning-ish. Nice to see you.") }
        else { react(.sleeping, "Just curling up for a little nap.") }
    }
}

enum Palette {
    static let ink = Color(red: 0.22, green: 0.27, blue: 0.23)
    static let muted = Color(red: 0.48, green: 0.51, blue: 0.44)
    static let cream = Color(red: 0.97, green: 0.96, blue: 0.92)
    static let green = Color(red: 0.37, green: 0.47, blue: 0.31)
    static let peach = Color(red: 0.93, green: 0.68, blue: 0.55)
}
