import Foundation

/// Opt-in development diagnostics. Never records text, keys, clipboard contents, or credentials.
@MainActor public enum InteractionTrace {
    public static let enabled = SociusStorage.isDevelopment
        && CommandLine.arguments.contains("--trace-interactions")
    private static let output: FileHandle? = {
        guard enabled else { return nil }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("socius-interactions.log")
        FileManager.default.createFile(atPath: file.path, contents: nil)
        return try? FileHandle(forWritingTo: file)
    }()

    public static func record(_ message: @autoclosure () -> String) {
        guard enabled else { return }
        try? output?.write(contentsOf: Data("\(Date().timeIntervalSince1970) \(message())\n".utf8))
    }
}
