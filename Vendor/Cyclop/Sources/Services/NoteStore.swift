import AppKit

struct Note: Identifiable, Codable, Equatable {
    let id: UUID
    var text: String
    var edited: Date
}

/// Scratch notes: somewhere to put a thought down for an hour.
///
/// Deliberately not a notes app. No folders, no formatting, no search — for
/// that there are real editors. This replaces the unsaved buffer people keep
/// in one: a phone number from a call, half a link, a thought to come back to
/// — written fast, then deleted or carried off through the clipboard.
///
/// Everything here is shaped by that shortness of life: notes are created
/// empty and instantly, deleted in one click, and the blank ones sweep
/// themselves out when the tab is left. The file they live in is an
/// implementation detail — unlike the snippets file, nobody is expected to
/// edit it by hand.
@MainActor
final class NoteStore: ObservableObject {
    @Published private(set) var notes: [Note] = []
    /// Which note the editor shows. Lives here rather than in the pane so the
    /// choice survives the pane being unmounted with the panel.
    @Published var selected: Note.ID?
    @Published private(set) var loadError: String?
    @Published private(set) var writeError: String?
    let file: URL
    private var loadedData: Data?

    private let saves = DebouncedWrite()

    init(file: URL = Support.file("notes.json")) {
        self.file = file
        load()
    }

    // MARK: - Editing

    /// A new empty note, selected and ready to type into. Newest on top, and
    /// the order never changes afterwards: a list that reshuffles itself on
    /// every edit loses the reader's place for tidiness nobody asked for.
    func add() {
        guard loadError == nil else { return }
        let note = Note(id: UUID(), text: "", edited: Date())
        notes.insert(note, at: 0)
        selected = note.id
        scheduleSave()
    }

    func update(_ id: Note.ID, text: String) {
        guard loadError == nil else { return }
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].text = text
        notes[index].edited = Date()
        scheduleSave()
    }

    func remove(_ id: Note.ID) {
        guard loadError == nil else { return }
        notes.removeAll { $0.id == id }
        if selected == id { selected = notes.first?.id }
        scheduleSave()
    }

    /// Called when the user leaves the tab: notes that never got any text
    /// sweep themselves out. They cost one hover to recreate, and a trail of
    /// blank cards is exactly the clutter a scratchpad exists to avoid.
    func leave() {
        guard loadError == nil else { return }
        let previous = notes
        notes.removeAll { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if let selected, !notes.contains(where: { $0.id == selected }) {
            self.selected = notes.first?.id
        }
        if notes != previous { scheduleSave() }
        flush()
    }

    // MARK: - Persistence

    private func load() {
        do {
            let data = try Data(contentsOf: file)
            notes = try JSONDecoder().decode([Note].self, from: data)
            loadedData = data
            selected = notes.first?.id
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            // Only an absent file is a safe empty store.
        } catch {
            loadError = "Couldn’t read notes.json. Your saved file is unchanged. Open it to check its contents and access, then reopen Socius."
        }
    }

    /// A moment after the typing pauses, not on every keystroke: the text
    /// lives in memory either way, and the file only has to be right by the
    /// time somebody could read it.
    private func scheduleSave() {
        saves.schedule { [weak self] in self?.persist() }
    }

    func flush() { saves.flush() }

    func reveal() { NSWorkspace.shared.activateFileViewerSelecting([file]) }

    private func persist() {
        guard loadError == nil else { return }
        do {
            let current: Data?
            do { current = try Data(contentsOf: file) }
            catch let error as CocoaError where error.code == .fileReadNoSuchFile { current = nil }
            guard current == loadedData else {
                writeError = "notes.json changed outside Socius. Copy your unsaved text before reopening the app; the saved file has not been overwritten."
                return
            }
            let data = try JSONEncoder().encode(notes)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
            loadedData = data
            writeError = nil
        } catch {
            writeError = "Couldn’t save notes. Your edits remain in this session. Check file access and keep a copy before quitting."
        }
    }
}
