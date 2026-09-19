import Foundation
import Darwin

/// Minimal terminal screen for the cursor-addressed output of Claude's built-in /usage.
nonisolated struct UsageTerminal {
    private var cells: [Int: [Int: Character]] = [:]
    private var row = 0
    private var column = 0
    private var saved = (0, 0)
    init(_ raw: String) {
        let chars = Array(raw)
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            if ch == "\u{1b}" {
                i += 1
                guard i < chars.count else { break }
                if chars[i] == "[" {
                    i += 1
                    var parameters = ""
                    while i < chars.count {
                        let code = chars[i].unicodeScalars.first!.value
                        if code >= 0x40 && code <= 0x7e { break }
                        parameters.append(chars[i]); i += 1
                    }
                    guard i < chars.count else { break }
                    let values = parameters.split(separator: ";", omittingEmptySubsequences: false).map { Int($0) ?? 0 }
                    let n = max(1, values.first ?? 1)
                    switch chars[i] {
                    case "A": row = max(0, row - n)
                    case "B": row += n
                    case "C": column += n
                    case "D": column = max(0, column - n)
                    case "G": column = n - 1
                    case "H", "f": row = n - 1; column = max(0, (values.count > 1 ? values[1] : 1) - 1)
                    case "K":
                        let mode = values.first ?? 0
                        cells[row] = cells[row, default: [:]].filter { mode == 0 ? $0.key < column : mode == 1 ? $0.key > column : false }
                    case "J":
                        if values.first == 2 { cells.removeAll() }
                        else { cells = cells.filter { $0.key < row }; cells[row] = [:] }
                    default: break
                    }
                } else if chars[i] == "]" {
                    while i < chars.count && chars[i] != "\u{7}" {
                        if chars[i] == "\u{1b}" && i + 1 < chars.count && chars[i + 1] == "\\" { i += 1; break }
                        i += 1
                    }
                } else if chars[i] == "7" { saved = (row, column) }
                else if chars[i] == "8" { (row, column) = saved }
                else if chars[i] == "(" { i += 1 }
            } else if ch == "\r" { column = 0 }
            else if ch == "\n" { row += 1 }
            else if ch == "\r\n" { row += 1; column = 0 }
            else if ch == "\u{8}" { column = max(0, column - 1) }
            else if ch.unicodeScalars.first!.value >= 32 {
                cells[row, default: [:]][column] = ch; column += 1
            }
            if row > 2000 { break }
            i += 1
        }
    }
    var text: String {
        cells.keys.sorted().map { row in
            let line = cells[row]!
            return (0...min(line.keys.max() ?? 0, 1000)).map { String(line[$0] ?? " ") }.joined()
                .trimmingCharacters(in: .whitespaces)
        }.joined(separator: "\n")
    }
}

nonisolated struct ClaudeCLIWindow: Sendable, Equatable {
    var name: String
    var used: Double
    var reset: String
}

nonisolated enum ClaudeCLIUsage {
    static func parse(_ screen: String) -> [ClaudeCLIWindow] {
        let lines = screen.components(separatedBy: .newlines)
        var result: [ClaudeCLIWindow] = []
        for index in lines.indices {
            let name = lines[index].trimmingCharacters(in: .whitespaces)
            guard name == "Current session" || name.hasPrefix("Current week (") else { continue }
            let following = lines[(index + 1)..<min(index + 6, lines.count)].prefix { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("Current ") }
            guard let meter = following.first(where: { $0.contains("%") && $0.contains("used") }),
                  let range = meter.range(of: #"\d+(?:\.\d+)?(?=%\s*used)"#, options: .regularExpression),
                  let used = Double(meter[range]), (0...100).contains(used),
                  let reset = following.first(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("Resets ") }) else { continue }
            result.append(ClaudeCLIWindow(name: name, used: used, reset: reset.trimmingCharacters(in: .whitespaces)))
        }
        return result
    }

    @concurrent static func read(executable: URL, directory: URL) async throws -> [ClaudeCLIWindow] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var master: Int32 = -1
        var slave: Int32 = -1
        var size = winsize(ws_row: 100, ws_col: 180, ws_xpixel: 0, ws_ypixel: 0)
        guard openpty(&master, &slave, nil, nil, &size) == 0 else { throw ToolError.message("Could not open Claude CLI terminal.") }
        let input = FileHandle(fileDescriptor: master, closeOnDealloc: true)
        let terminal = FileHandle(fileDescriptor: slave, closeOnDealloc: true)
        let process = Process()
        process.executableURL = executable
        process.currentDirectoryURL = directory
        process.arguments = ["--setting-sources", "", "--strict-mcp-config", "--mcp-config", "{\"mcpServers\":{}}",
                             "--settings", "{\"disableAllHooks\":true}", "--tools", "", "--permission-mode", "manual"]
        process.standardInput = terminal; process.standardOutput = terminal; process.standardError = terminal
        var environment = ProcessInfo.processInfo.environment
        environment["TERM"] = "xterm-256color"
        environment["PATH"] = "\(FileManager.default.homeDirectoryForCurrentUser.path)/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        process.environment = environment
        try process.run()
        defer {
            if process.isRunning { process.terminate() }
            try? terminal.close(); try? input.close()
        }
        let began = Date()
        var output = Data()
        var sentUsageAt: Date?
        var acceptedOwnFolder = false
        while Date().timeIntervalSince(began) < 20 {
            try Task.checkCancellation()
            var descriptor = pollfd(fd: master, events: Int16(POLLIN), revents: 0)
            if poll(&descriptor, 1, 150) > 0 {
                var buffer = [UInt8](repeating: 0, count: 16384)
                let count = Darwin.read(master, &buffer, buffer.count)
                if count > 0 { output.append(contentsOf: buffer.prefix(count)) }
            }
            guard output.count < 1_000_000 else { throw ToolError.message("Claude CLI output exceeded the expected size.") }
            let screen = UsageTerminal(String(decoding: output, as: UTF8.self)).text
            if Date().timeIntervalSince(began) > 1 && !acceptedOwnFolder && screen.contains("Yes, I trust this folder") && (screen.contains(directory.path) || screen.contains(directory.resolvingSymlinksInPath().path) || screen.contains((directory.path as NSString).abbreviatingWithTildeInPath)) {
                // This is our dedicated directory, with tools, hooks and MCP disabled.
                try input.write(contentsOf: Data("\u{1b}[B".utf8))
                try await Task.sleep(for: .milliseconds(150))
                try input.write(contentsOf: Data("\r".utf8))
                acceptedOwnFolder = true
            }
            if Date().timeIntervalSince(began) > 1 && sentUsageAt == nil && screen.contains("Claude Code v") && screen.contains("❯") && !screen.contains("Yes, I trust this folder") {
                try input.write(contentsOf: Data("/usage\r".utf8))
                sentUsageAt = Date()
            }
            if let sentUsageAt, Date().timeIntervalSince(sentUsageAt) > 3,
               !screen.contains("Refreshing…") {
                let windows = parse(screen)
                if windows.contains(where: { $0.name == "Current week (all models)" }),
                   windows.contains(where: { $0.name == "Current session" }) { return windows }
            }
            if !process.isRunning { break }
        }
        throw ToolError.message("Claude CLI did not return a complete /usage screen. Open Claude Code and check /usage or sign in again.")
    }
}
