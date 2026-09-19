import AppKit
import Observation

enum PocketTool: String, CaseIterable, Identifiable {
    case shelf = "Shelf", clipboard = "Clipboard", music = "Music", snippets = "Snippets", notes = "Notes", usage = "AI Credits", layouts = "Layouts"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .shelf: "square.stack.3d.up"
        case .clipboard: "doc.on.clipboard"
        case .music: "music.note"
        case .snippets: "text.quote"
        case .notes: "note.text"
        case .usage: "chart.bar"
        case .layouts: "rectangle.3.group"
        }
    }
}

struct TextItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var text: String
    var updatedAt = Date()
}

struct ClipboardItem: Identifiable, Equatable {
    var id = UUID()
    var text: String?
    var png: Data?
    var date = Date()
}

struct ShelfItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var path: String
    var addedAt = Date()
    var url: URL { URL(fileURLWithPath: path) }
}

struct ToolData: Codable {
    var snippets: [TextItem] = []
    var notes: [TextItem] = []
    var shelf: [ShelfItem] = []
    var layouts: [WindowLayout] = []
    var screenshotFolder: String?
    var clipboardEnabled = true
    var clipboardDefaultVersion: Int? = 1
}

enum ToolError: LocalizedError {
    case message(String)
    var errorDescription: String? { switch self { case .message(let message): message } }
}

@Observable final class ToolStore {
    private(set) var data = ToolData()
    private(set) var clipboard: [ClipboardItem] = []
    var notice: String?
    var textDrafts: [PocketTool: TextItem] = [:]
    private(set) var isChoosingFiles = false
    private(set) var filePickerFinished = 0
    func setExternalFilePicker(_ choosing: Bool) {
        isChoosingFiles = choosing
        if !choosing { filePickerFinished += 1 }
    }
    private(set) var loadError: String?
    let directory: URL
    private let pasteboard: NSPasteboard
    private var pasteboardChange: Int
    private var polling: Task<Void, Never>?
    private var filePanel: NSOpenPanel?
    private var seenImages = Set<String>()

    init(directory: URL? = nil, pasteboard: NSPasteboard = .general) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Socius")
        self.pasteboard = pasteboard
        pasteboardChange = pasteboard.changeCount
        let file = self.directory.appendingPathComponent("tools.json")
        do {
            try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: file.path) {
                data = try JSONDecoder().decode(ToolData.self, from: Data(contentsOf: file))
                if data.clipboardDefaultVersion == nil {
                    // One-time migration to the user's requested automatic collection default.
                    data.clipboardEnabled = true
                    data.clipboardDefaultVersion = 1
                    try JSONEncoder().encode(data).write(to: file, options: .atomic)
                }
            }
        } catch { loadError = "Saved tools could not be loaded. Your file has been preserved: \(error.localizedDescription)" }
    }

    func start() {
        guard polling == nil else { return }
        polling = Task { [weak self] in
            var ticks = 0
            while !Task.isCancelled {
                self?.pollClipboard()
                if ticks % 10 == 0 { self?.scanScreenshots() }
                ticks += 1
                do { try await Task.sleep(for: .milliseconds(700)) } catch { return }
            }
        }
    }
    func stop() { polling?.cancel(); polling = nil }

    /// Commit only after an atomic disk write succeeds, so the UI never claims an unsaved edit succeeded.
    @discardableResult func update(_ change: (inout ToolData) -> Void) -> Bool {
        guard loadError == nil else { notice = loadError; return false }
        var next = data
        change(&next)
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(next).write(to: directory.appendingPathComponent("tools.json"), options: .atomic)
            data = next
            return true
        } catch { notice = "Could not save: \(error.localizedDescription)"; return false }
    }

    func setClipboardEnabled(_ enabled: Bool) {
        pasteboardChange = pasteboard.changeCount
        update { $0.clipboardEnabled = enabled }
    }
    func clearClipboard() { clipboard.removeAll() }
    func removeClip(_ id: UUID) { clipboard.removeAll { $0.id == id } }
    func pollClipboard() {
        guard pasteboard.changeCount != pasteboardChange else { return }
        pasteboardChange = pasteboard.changeCount
        let excluded = ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType", "org.nspasteboard.AutoGeneratedType"]
        guard data.clipboardEnabled,
              !excluded.contains(where: { pasteboard.availableType(from: [.init($0)]) != nil }) else { return }
        if let text = pasteboard.string(forType: .string), !text.isEmpty, text.utf8.count <= 1_000_000 {
            record(ClipboardItem(text: text))
        } else if let png = pasteboard.data(forType: .png), png.count <= 5_000_000 {
            record(ClipboardItem(png: png))
        } else if let tiff = pasteboard.data(forType: .tiff), tiff.count <= 5_000_000,
                  let image = NSBitmapImageRep(data: tiff), let png = image.representation(using: .png, properties: [:]), png.count <= 5_000_000 {
            record(ClipboardItem(png: png))
        }
    }
    func record(_ item: ClipboardItem) {
        guard item.text != nil || item.png != nil else { return }
        clipboard.removeAll { $0.text == item.text && $0.png == item.png }
        clipboard.insert(item, at: 0)
        clipboard = Array(clipboard.prefix(40))
    }
    func copy(_ text: String) {
        pasteboard.clearContents()
        let ok = pasteboard.setString(text, forType: .string)
        pasteboardChange = pasteboard.changeCount
        notice = ok ? "Copied. Ready to paste." : "Could not copy. Try again."
    }
    func copy(_ item: ClipboardItem) {
        if let text = item.text { copy(text); return }
        guard let png = item.png else { return }
        pasteboard.clearContents()
        let ok = pasteboard.setData(png, forType: .png)
        pasteboardChange = pasteboard.changeCount
        notice = ok ? "Image copied. Ready to paste." : "Could not copy the image."
    }
    func copyFile(_ item: ShelfItem) {
        guard FileManager.default.fileExists(atPath: item.path) else { notice = "This file has moved or been deleted."; return }
        pasteboard.clearContents()
        let ok = pasteboard.writeObjects([item.url as NSURL])
        pasteboardChange = pasteboard.changeCount
        notice = ok ? "File copied. Ready to paste." : "Could not copy this file."
    }

    func saveText(_ item: TextItem, in tool: PocketTool) -> Bool {
        guard tool == .notes || tool == .snippets else { return false }
        var saved = item
        saved.title = saved.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if saved.title.isEmpty { saved.title = String(saved.text.prefix(40)).trimmingCharacters(in: .whitespacesAndNewlines) }
        guard !saved.title.isEmpty else { notice = "Add a title or some text first."; return false }
        saved.updatedAt = Date()
        return update {
            if tool == .notes { $0.notes.removeAll { $0.id == saved.id }; $0.notes.insert(saved, at: 0) }
            else { $0.snippets.removeAll { $0.id == saved.id }; $0.snippets.insert(saved, at: 0) }
        }
    }
    func removeText(_ id: UUID, in tool: PocketTool) {
        update { if tool == .notes { $0.notes.removeAll { $0.id == id } } else { $0.snippets.removeAll { $0.id == id } } }
    }
    func addFiles(_ urls: [URL]) {
        let valid = urls.filter { $0.isFileURL && FileManager.default.fileExists(atPath: $0.path) }
        guard !valid.isEmpty else { return }
        update { next in
            for url in valid {
                next.shelf.removeAll { $0.path == url.path }
                next.shelf.insert(ShelfItem(path: url.path), at: 0)
            }
            next.shelf = Array(next.shelf.prefix(100))
        }
    }
    func chooseFiles() {
        guard filePanel == nil else { return }
        isChoosingFiles = true
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.prompt = "Add to Shelf"
        presentFilePanel(panel) { [weak self] urls in self?.addFiles(urls) }
    }
    func chooseScreenshotFolder() {
        guard filePanel == nil else { return }
        isChoosingFiles = true
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.message = "Choose your screenshots folder. Its newest 20 images will appear on your Shelf."
        panel.prompt = "Watch folder"
        presentFilePanel(panel) { [weak self] urls in
            guard let self, let url = urls.first, self.update({ $0.screenshotFolder = url.path }) else { return }
            self.seenImages.removeAll(); self.scanScreenshots()
        }
    }
    private func presentFilePanel(_ panel: NSOpenPanel, completion: @escaping ([URL]) -> Void) {
        filePanel = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.level = .modalPanel
        panel.begin { [weak self] response in
            if response == .OK { completion(panel.urls) }
            self?.filePanel = nil
            self?.isChoosingFiles = false
            self?.filePickerFinished += 1
        }
        panel.makeKeyAndOrderFront(nil)
    }
    func scanScreenshots() {
        guard let path = data.screenshotFolder else { return }
        do {
            let urls = try FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: path), includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey], options: .skipsHiddenFiles)
            let recent = urls.compactMap { url -> (URL, Date)? in
                guard ["png", "jpg", "jpeg", "heic", "tiff"].contains(url.pathExtension.lowercased()),
                      let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]), values.isRegularFile == true else { return nil }
                return (url, values.contentModificationDate ?? .distantPast)
            }.sorted { $0.1 > $1.1 }.prefix(20).map(\.0)
            // Compare against persisted items separately, avoiding re-adding files a user removed this session.
            let existing = Set(data.shelf.map(\.path))
            let additions = recent.filter { !seenImages.contains($0.path) && !existing.contains($0.path) }
            if !additions.isEmpty { addFiles(additions.reversed()) }
            seenImages.formUnion(recent.map(\.path))
        } catch { notice = "Screenshot folder unavailable. Choose the folder again in Shelf." }
    }
}
