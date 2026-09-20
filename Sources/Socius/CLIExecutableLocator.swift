import Foundation

/// GUI apps do not inherit the interactive shell's PATH. Search common package
/// managers directly; never launch a shell or execute the user's startup files.
nonisolated enum CLIExecutableLocator {
    static func claude(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                       path: String = ProcessInfo.processInfo.environment["PATH"] ?? "",
                       systemDirectories: [String] = ["/opt/homebrew/bin", "/usr/local/bin"]) -> URL? {
        let fm = FileManager.default
        var directories = [home.appendingPathComponent(".local/bin").path] + systemDirectories
        directories += path.split(separator: ":").map(String.init).filter { $0.hasPrefix("/") }
        directories += [".npm-global/bin", ".npm/bin", ".volta/bin", ".asdf/shims", ".bun/bin", "Library/pnpm"].map { home.appendingPathComponent($0).path }
        for (base, suffix) in [(".nvm/versions/node", "bin"), (".local/share/fnm/node-versions", "installation/bin"), ("Library/Application Support/fnm/node-versions", "installation/bin")] {
            let root = home.appendingPathComponent(base)
            let versions = (try? fm.contentsOfDirectory(atPath: root.path)) ?? []
            directories += versions.sorted { $0.compare($1, options: .numeric) == .orderedDescending }
                .map { root.appendingPathComponent($0).appendingPathComponent(suffix).path }
        }
        return directories.map { URL(fileURLWithPath: $0).appendingPathComponent("claude") }
            .first { fm.isExecutableFile(atPath: $0.path) }
    }
    static func runtimePath(for executable: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [executable.deletingLastPathComponent().path, executable.resolvingSymlinksInPath().deletingLastPathComponent().path,
                home + "/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin",
                ProcessInfo.processInfo.environment["PATH"] ?? ""].joined(separator: ":")
    }
}
