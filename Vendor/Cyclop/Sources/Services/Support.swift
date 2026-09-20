import Foundation

/// `~/Library/Application Support/Cyclop` — where everything Cyclop keeps of
/// its own lives.
///
/// One place for the path, because four stores were each spelling out the same
/// three lines: find the support directory, append the app's name, make sure it
/// exists. Identical every time, and the kind of thing that stays identical
/// only until one copy is edited and the others are not.
public enum SociusStorage {
    public static var isDevelopment: Bool {
        Bundle.main.object(forInfoDictionaryKey: "SociusBuildChannel") as? String != "release"
    }
    public static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(isDevelopment ? "Socius/Development" : "Socius", isDirectory: true)
    }
    public static var preferences: UserDefaults {
        let developmentID = "app.socius.desktop.development"
        // Bundled development apps already use this domain as their standard
        // defaults. macOS rejects creating a suite with the app's own identifier.
        guard isDevelopment, Bundle.main.bundleIdentifier != developmentID else { return .standard }
        return UserDefaults(suiteName: developmentID) ?? .standard
    }
}

enum Support {
    static let isPreview = ProcessInfo.processInfo.arguments.contains("--render-preview")
        || ProcessInfo.processInfo.arguments.contains(where: { $0.contains(".xctest") })
        || Bundle.allBundles.contains(where: { $0.bundlePath.hasSuffix(".xctest") })
    /// The folder itself, created on first use. Repeated calls are cheap —
    /// `createDirectory` with `withIntermediateDirectories` is content to find
    /// the folder already there.
    static let folder: URL = {
        let fm = FileManager.default
        if Self.isPreview {
            let preview = fm.temporaryDirectory.appendingPathComponent("socius-cyclop-preview-\(ProcessInfo.processInfo.processIdentifier)")
            try? fm.createDirectory(at: preview, withIntermediateDirectories: true)
            return preview
        }
        let url = SociusStorage.directory.appendingPathComponent("Cyclop", isDirectory: true)
        try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    /// A file inside it, with the folder guaranteed to exist by the time the
    /// path is handed back — which is the only reason this is a function and
    /// not string concatenation at the call site.
    static func file(_ name: String) -> URL {
        folder.appendingPathComponent(name)
    }

    /// A subfolder inside it, created the same way.
    static func directory(_ name: String) -> URL {
        let url = folder.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

/// Keep native previews and test hosts away from the running app’s preferences.
@MainActor enum PocketDefaults {
    static let shared: UserDefaults = Support.isPreview ? UserDefaults(suiteName: "Socius.Preview.\(ProcessInfo.processInfo.processIdentifier)")! : SociusStorage.preferences
}
