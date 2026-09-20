import AppKit
import Observation
import OSLog

/// Records connection stages, never provider output, account data, tokens, or paths.
@Observable final class UsageDiagnostics {
    private(set) var entries: [String] = []
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "app.socius.desktop.development", category: "AI Credits")

    func record(_ provider: String, _ event: String) {
        let line = "\(Date().ISO8601Format()) \(provider): \(event)"
        entries.append(line)
        if entries.count > 100 { entries.removeFirst(entries.count - 100) }
        logger.info("\(line, privacy: .public)")
    }

    func failure(_ provider: String, _ error: Error) {
        if error is CancellationError { record(provider, "cancelled"); return }
        let native = error as NSError
        record(provider, "failed (\(String(reflecting: type(of: error))), code \(native.code))")
    }

    var text: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
        return (["Socius \(version)", "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)"] + entries).joined(separator: "\n")
    }

    func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
