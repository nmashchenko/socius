import SwiftUI
import AppKit

/// Socius host adapter. The pane and service implementations live alongside this file.
@MainActor public final class CyclopPocket: ObservableObject {
    let shelf = ShelfStore()
    let clipboard = ClipboardStore()
    let snippets: SnippetStore
    let notes: NoteStore
    let media = MediaController()
    let privacy = PrivacyMode()
    let screenshots = ScreenshotFolderWatcher()
    @Published public var choosingFiles = false
    @Published public var rememberCopies: Bool {
        didSet {
            PocketDefaults.shared.set(rememberCopies, forKey: "cyclop.rememberCopies")
            if started { rememberCopies ? clipboard.start() : clipboard.stop() }
        }
    }
    private var started = false
    private(set) var panel: NSOpenPanel?

    public init(legacyFile: URL) {
        Self.migrate(legacyFile)
        snippets = SnippetStore()
        notes = NoteStore()
        rememberCopies = PocketDefaults.shared.object(forKey: "cyclop.rememberCopies") as? Bool ?? true
        shelf.load()
        snippets.reload()
    }

    public func start() {
        guard !started else { return }
        started = true
        clipboard.wantsImages = { ConfigStore.shared.saveClipboardImages }
        clipboard.onImage = { [weak self] png in
            guard let url = ScreenshotVault.save(png) else { return }
            self?.shelf.add([url])
        }
        screenshots.onImage = { [weak self] url in self?.shelf.add([url]) }
        if rememberCopies { clipboard.start() }
        screenshots.resumeIfEnabled()
        media.start()
    }

    public func stop() {
        started = false
        clipboard.stop()
        screenshots.stop()
        media.stop()
        notes.flush()
    }

    func addFiles() {
        guard panel == nil else { return }
        let picker = NSOpenPanel()
        picker.allowsMultipleSelection = true
        picker.canChooseDirectories = true
        picker.prompt = "Add to Shelf"
        panel = picker
        choosingFiles = true
        NSApp.activate(ignoringOtherApps: true)
        picker.level = .modalPanel
        picker.begin { [weak self] result in
            guard let self else { return }
            if result == .OK { shelf.add(picker.urls) }
            panel = nil
            choosingFiles = false
        }
        picker.makeKeyAndOrderFront(nil)
    }

    func watchScreenshots() {
        choosingFiles = true
        NSApp.activate(ignoringOtherApps: true)
        screenshots.requestAccess { [weak self] _ in self?.choosingFiles = false }
    }

    // One-time import; the original tools.json remains intact for rollback.
    private static func migrate(_ file: URL) {
        let marker = Support.file("socius-import-v1")
        guard !FileManager.default.fileExists(atPath: marker.path) else { return }
        guard let data = try? Data(contentsOf: file),
              let legacy = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        do {
            for (key, rows) in [
                ("snippets", (legacy["snippets"] as? [[String: Any]] ?? []).map { ["label": $0["title"] ?? "", "text": $0["text"] ?? ""] }),
                ("notes", (legacy["notes"] as? [[String: Any]] ?? []).map { row -> [String: Any] in
                    let title = row["title"] as? String ?? ""
                    let text = row["text"] as? String ?? ""
                    let body = title.isEmpty || text.hasPrefix(title) ? text : title + "\n\n" + text
                    return ["id": row["id"] ?? UUID().uuidString, "text": body, "edited": row["updatedAt"] ?? Date().timeIntervalSinceReferenceDate]
                })
            ] {
                let target = Support.file(key + ".json")
                if !FileManager.default.fileExists(atPath: target.path) {
                    try JSONSerialization.data(withJSONObject: rows).write(to: target, options: .atomic)
                }
            }
            if PocketDefaults.shared.object(forKey: "shelf.urls") == nil {
                let paths = (legacy["shelf"] as? [[String: Any]] ?? []).compactMap { $0["path"] as? String }
                PocketDefaults.shared.set(paths, forKey: "shelf.urls")
            }
            if let folder = legacy["screenshotFolder"] as? String, PocketDefaults.shared.object(forKey: "screenshotFolderWatch.path") == nil {
                PocketDefaults.shared.set(folder, forKey: "screenshotFolderWatch.path")
                PocketDefaults.shared.set(true, forKey: "screenshotFolderWatch.enabled")
            }
            if PocketDefaults.shared.object(forKey: "cyclop.rememberCopies") == nil {
                PocketDefaults.shared.set(legacy["clipboardEnabled"] as? Bool ?? true, forKey: "cyclop.rememberCopies")
            }
            try Data().write(to: marker, options: .atomic)
        } catch { NSLog("Socius: could not import legacy tools: %@", error.localizedDescription) }
    }
}

public struct CyclopPocketPane: View {
    @ObservedObject var pocket: CyclopPocket
    let tool: String
    @State private var wantsKeyboard = true
    @State private var targeted = false

    public init(pocket: CyclopPocket, tool: String) {
        self.pocket = pocket
        self.tool = tool
    }

    public var body: some View {
        content
            .buttonStyle(.plain)
            .tint(Theme.ink)
            .onAppear {
                if tool == "Shelf" { pocket.shelf.refreshFromDisk() }
                if tool == "Snippets" { pocket.snippets.reload() }
                if tool == "Music" { pocket.media.setActive(true) }
            }
            .onDisappear {
                if tool == "Notes" { pocket.notes.leave(); pocket.notes.flush() }
                if tool == "Music" { pocket.media.setActive(false) }
            }
    }

    @ViewBuilder private var content: some View {
        switch tool {
        case "Shelf":
            VStack(alignment: .leading, spacing: PocketMetrics.sectionGap) {
                HStack {
                    Button("Add files…", action: pocket.addFiles)
                    Button("Watch screenshots…", action: pocket.watchScreenshots)
                }.buttonStyle(PocketToolbarButton())
                ShelfPane(shelf: pocket.shelf, isTargeted: targeted)
                    .dropDestination(for: URL.self) { urls, _ in
                        pocket.shelf.add(urls)
                        return true
                    } isTargeted: { targeted = $0 }
            }
        case "Clipboard":
            VStack(alignment: .leading, spacing: PocketMetrics.sectionGap) {
                HStack {
                    Toggle("Remember copies", isOn: $pocket.rememberCopies).toggleStyle(NotchToggleStyle())
                    Text("Remember copies").font(.system(size: 12))
                    Spacer()
                    Text("Last 40").font(.system(size: 11)).foregroundStyle(Theme.secondary)
                }
                ClipboardPane(clipboard: pocket.clipboard, privacy: pocket.privacy)
            }
        case "Snippets": SnippetsPane(snippets: pocket.snippets, privacy: pocket.privacy, wantsKeyboard: $wantsKeyboard)
        case "Notes": NotesPane(notes: pocket.notes, privacy: pocket.privacy, wantsKeyboard: $wantsKeyboard)
        case "Music": MediaPane(media: pocket.media)
        default: EmptyView()
        }
    }
}

private struct PocketToolbarButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 11, weight: .medium))
            .foregroundStyle(Theme.ink).padding(.horizontal, 10).frame(height: 30)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 9))
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}
