import Foundation

struct TextItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var text: String
    var updatedAt = Date()
}
struct Clip: Identifiable, Equatable {
    var id = UUID()
    var text: String
    var date = Date()
}
struct ShelfItem: Codable, Identifiable {
    var id = UUID()
    var path: String
    var addedAt = Date()
    var url: URL { URL(fileURLWithPath: path) }
}
struct SavedWindow: Codable, Identifiable {
    var id = UUID()
    var bundleID: String
    var title: String
    var windowIndex: Int
    var screenID: UInt32
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}
struct WindowLayout: Codable, Identifiable {
    var id = UUID()
    var name: String
    var windows: [SavedWindow]
}
struct PetState: Codable {
    var name = "Mochi"
    var birthday = Date()
    var lastFed = Date()
    var lastPlayed = Date()
    var helpfulActions = 0
    var sleeping = false
    var happiness: Double { max(0.15, 1 - Date().timeIntervalSince(lastPlayed) / 172800) }
    var fullness: Double { max(0.1, 1 - Date().timeIntervalSince(lastFed) / 86400) }
    var level: Int { 1 + helpfulActions / 20 }
}
struct AppData: Codable {
    var snippets: [TextItem] = []
    var notes: [TextItem] = []
    var shelf: [ShelfItem] = []
    var layouts: [WindowLayout] = []
    var pet = PetState()
    var screenshotFolder: String?
}
struct UsageWindow: Identifiable {
    var id: String { name }
    var name: String
    var used: Double
    var resetsAt: Date?
    var remaining: Double { max(0, 100 - used) }
    var expired: Bool { resetsAt.map { $0 < Date() } ?? false }
}
struct ProviderUsage {
    var windows: [UsageWindow] = []
    var updatedAt: Date?
    var message: String
}

enum UsageParser {
    static func codex(_ data: Data) throws -> [UsageWindow] {
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let result = root["result"] as? [String: Any] ?? root
        if let error = root["error"] as? [String: Any] {
            throw AppError.message(error["message"] as? String ?? "Codex could not read account limits.")
        }
        let byID = result["rateLimitsByLimitId"] as? [String: Any]
        let limits = byID?["codex"] as? [String: Any] ?? result["rateLimits"] as? [String: Any] ?? [:]
        return ["primary", "secondary"].compactMap { key in
            guard let window = limits[key] as? [String: Any], let used = window["usedPercent"] as? Double, used.isFinite else { return nil }
            let minutes = window["windowDurationMins"] as? Int
            let label = minutes.map { $0 >= 1440 ? "\($0 / 1440)-day limit" : "\($0 / 60)-hour limit" } ?? key.capitalized
            return UsageWindow(name: label, used: min(100, max(0, used)), resetsAt: (window["resetsAt"] as? Double).map(Date.init(timeIntervalSince1970:)))
        }
    }
    static func claude(_ data: Data) throws -> [UsageWindow] {
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let limits = root["rate_limits"] as? [String: Any] ?? [:]
        return [("five_hour", "5-hour limit"), ("seven_day", "7-day limit"), ("spend_limit", "Spend limit")].compactMap { key, name in
            guard let window = limits[key] as? [String: Any], let used = window["used_percentage"] as? Double, used.isFinite else { return nil }
            return UsageWindow(name: name, used: min(100, max(0, used)), resetsAt: (window["resets_at"] as? Double).map(Date.init(timeIntervalSince1970:)))
        }
    }
}
enum AppError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let message) = self { message } else { nil } }
}
