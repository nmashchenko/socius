import Foundation
import Security
import LocalAuthentication

/// Reads only Claude Code's credential entry, and sends it only to Anthropic.
enum ClaudeAccountUsage {
    @concurrent static func read(allowAuthorization: Bool = false) async throws -> Data {
        let context = LAContext()
        context.interactionNotAllowed = !allowAuthorization
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        let credential = status == errSecSuccess ? result as? Data : nil
        guard let credential,
              let root = try? JSONSerialization.jsonObject(with: credential) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty else {
            throw ToolError.message("Claude sign-in access is unavailable. Authorize Claude usage above; if no sign-in is found, sign in to Claude Code first.")
        }
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.timeoutInterval = 12
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        let session = URLSession(configuration: config, delegate: ClaudeUsageRedirectPolicy(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw ToolError.message((response as? HTTPURLResponse)?.statusCode == 429
                ? "Claude is limiting usage refreshes. Try again in five minutes."
                : "Claude account refresh failed. Sign in again in Claude Code if your session expired.")
        }
        return data
    }
}

/// A usage read has one destination; never follow a redirect with account credentials.
nonisolated private final class ClaudeUsageRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

extension UsageParser {
    static func claudeAccount(_ data: Data) throws -> [UsageWindow] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ToolError.message("Unreadable Claude account response.")
        }
        let keys = ["five_hour", "seven_day"] + root.keys.filter { $0.hasPrefix("seven_day_") }.sorted()
        let iso = ISO8601DateFormatter()
        return keys.compactMap { key in
            guard let value = root[key] as? [String: Any], let used = value["utilization"] as? Double,
                  used.isFinite, (0...100).contains(used) else { return nil }
            let name = key == "five_hour" ? "Current session" : key == "seven_day" ? "Weekly · all models" : "Weekly · " + key.replacingOccurrences(of: "seven_day_", with: "").capitalized
            let reset = (value["resets_at"] as? String).flatMap { text in
                iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let date = iso.date(from: text) { return date }
                iso.formatOptions = [.withInternetDateTime]
                return iso.date(from: text)
            }
            return UsageWindow(id: key, name: name, used: used, resetsAt: reset)
        }
    }
}
