import AppKit
import UniformTypeIdentifiers

/// Watches the folder `screencapture` writes file-based screenshots into —
/// ⌘⇧3/⌘⇧4 without holding Ctrl, which save straight to disk and never touch
/// the pasteboard, so `ClipboardStore` never sees them (#18).
///
/// Off by default and never watches on its own: since Catalina, macOS gates
/// programmatic access to Desktop/Documents/Downloads behind a Privacy
/// prompt for every app, sandboxed or not — the one exception is a folder
/// the user hands over through a standard Open panel, which counts as
/// consent on its own and asks nothing further. `requestAccess` is that
/// panel; nothing here reads the folder before it has been called once and
/// approved.
@MainActor
final class ScreenshotFolderWatcher {
    /// A new screenshot file, ready to go on the shelf.
    var onImage: ((URL) -> Void)?
    var onAccessError: (() -> Void)?
    var onStateChanged: (() -> Void)?
    private(set) var activeFolder: URL?
    private var generation = 0
    private var accessPanel: NSOpenPanel?

    private let enabledKey = "screenshotFolderWatch.enabled"
    private let pathKey = "screenshotFolderWatch.path"

    private var source: DispatchSourceFileSystemObject?
    /// Names already accounted for — either seen at watch-start or already
    /// handed to `onImage`. Keeps a rename or a second write to the same
    /// name from being reported twice.
    private var seen: Set<String> = []

    var isEnabled: Bool {
        PocketDefaults.shared.bool(forKey: enabledKey)
    }

    var folderPath: String? {
        PocketDefaults.shared.string(forKey: pathKey)
    }

    /// Where `screencapture` saves files today — read the same preference it
    /// does, so the picker opens on the folder that actually fills up.
    static var systemLocation: URL {
        if let path = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location"),
           !path.isEmpty {
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop", isDirectory: true)
    }

    /// Puts up the Open panel that stands in for a Privacy prompt. Starts
    /// watching immediately on approval; changes nothing on cancel.
    func requestAccess(completion: @escaping (Bool) -> Void) {
        guard accessPanel == nil else { completion(false); return }
        let panel = NSOpenPanel()
        accessPanel = panel
        panel.level = .modalPanel
        panel.title = localized("Choose Screenshots Folder")
        panel.message = localized(
            "Socius will watch this folder for new screenshots and add them to the shelf."
        )
        panel.prompt = localized("Watch")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = Self.systemLocation
        panel.begin { [weak self] response in
            guard let self else { completion(false); return }
            self.accessPanel = nil
            guard response == .OK, let url = panel.url else {
                completion(false)
                return
            }
            guard self.start(at: url) else {
                self.onAccessError?()
                completion(false)
                return
            }
            PocketDefaults.shared.set(url.path, forKey: self.pathKey)
            PocketDefaults.shared.set(true, forKey: self.enabledKey)
            completion(true)
        }
        panel.makeKeyAndOrderFront(nil)
    }

    /// Called at launch. Silent — the folder was already granted once, so
    /// resuming asks nothing further.
    func resumeIfEnabled() {
        guard isEnabled, let folderPath else { return }
        if !start(at: URL(fileURLWithPath: folderPath, isDirectory: true)) {
            PocketDefaults.shared.set(false, forKey: enabledKey)
            onAccessError?()
        }
    }

    /// The Settings tab's off switch. Clears the grant along with the watch, so
    /// turning it back on goes through the panel again rather than silently
    /// resuming access nobody remembers giving.
    func disable() {
        PocketDefaults.shared.set(false, forKey: enabledKey)
        PocketDefaults.shared.removeObject(forKey: pathKey)
        stop()
    }

    func stop() {
        source?.cancel()
        source = nil
        generation += 1
        activeFolder = nil
        onStateChanged?()
    }

    @discardableResult
    func start(at folder: URL) -> Bool {
        guard let entries = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return false }
        let names = Set(entries.map(\.lastPathComponent))

        let fd = open(folder.path, O_EVTONLY)
        guard fd >= 0 else { return false }
        stop()
        seen = names
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .delete, .rename, .revoke], queue: .main
        )
        // Очередь здесь — главная, и это условие работоспособности, а не
        // удобство. Замыкание, записанное внутри `@MainActor`-типа, изоляцию
        // этого типа наследует — у `setEventHandler` параметр не помечен
        // `@Sendable`, проверено компилятором, — и рантайм сверяет её при
        // каждом вызове. С фоновой очередью проверка не прошла бы, и процесс
        // снимался бы на первом же изменении папки. Менять `queue` без
        // `@Sendable` на обоих обработчиках нельзя.
        let currentGeneration = generation
        source.setEventHandler { [weak self] in
            guard let self, self.generation == currentGeneration, let source = self.source else { return }
            if !source.data.intersection([.delete, .rename, .revoke]).isEmpty {
                self.disable()
                self.onAccessError?()
                return
            }
            self.scan(folder)
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        self.source = source
        activeFolder = folder
        onStateChanged?()
        return true
    }

    /// A directory `.write` event fires for any change to its listing — new
    /// file, rename, delete — so this diffs against `seen` rather than
    /// trusting the event to mean "a screenshot arrived".
    private func scan(_ folder: URL) {
        guard let urls = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            stop()
            PocketDefaults.shared.set(false, forKey: enabledKey)
            onAccessError?()
            return
        }
        seen.formIntersection(urls.map(\.lastPathComponent))
        for url in urls {
            let name = url.lastPathComponent
            guard !seen.contains(name) else { continue }
            seen.insert(name)
            guard let type = UTType(filenameExtension: url.pathExtension),
                  type.conforms(to: .image) else { continue }
            waitForStableSize(url, lastSize: -1, attempt: 0, generation: generation)
        }
    }

    /// `screencapture` writes the file in one shot, but checking twice for a
    /// steady size costs nothing and guards against a half-written file on a
    /// slow volume — the same caution `ClipboardStore.awaitImage` uses for
    /// screenshots arriving over Continuity.
    private func waitForStableSize(_ url: URL, lastSize: Int, attempt: Int, generation: Int) {
        guard generation == self.generation, source != nil else { return }
        guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? Int else {
            return
        }
        if size == lastSize && size > 0 {
            onImage?(url)
            return
        }
        guard attempt < 10 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.waitForStableSize(url, lastSize: size, attempt: attempt + 1, generation: generation)
        }
    }

}
