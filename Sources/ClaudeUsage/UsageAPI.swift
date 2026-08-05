import Foundation

enum UsageAPIError: LocalizedError {
    case unauthorised
    case rateLimited(retryAfter: TimeInterval?)
    case http(Int, String)
    case unreadable(String)

    var errorDescription: String? {
        switch self {
        case .unauthorised:
            return "Claude rejected the token. Run `claude` once to refresh your sign-in."
        case .rateLimited:
            return "Claude is rate limiting the usage endpoint. Showing the last reading."
        case .http(let code, let body):
            return "Usage request failed (\(code)). \(body.prefix(180))"
        case .unreadable:
            return "Usage response was not in a shape the app recognises."
        }
    }

    /// The body is kept so the panel's diagnostics can show what actually came back.
    var payload: String? {
        switch self {
        case .http(_, let body), .unreadable(let body): return body
        case .unauthorised, .rateLimited: return nil
        }
    }
}

struct UsageAPI {
    static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    var credentials: () throws -> OAuthCredentials = Keychain.claudeCredentials

    func fetch() async throws -> Usage {
        let token = try credentials().accessToken

        var request = URLRequest(url: Self.endpoint)
        request.timeoutInterval = 15
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("ClaudeUsage/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        let http = response as? HTTPURLResponse
        let code = http?.statusCode ?? 0
        let body = String(data: data, encoding: .utf8) ?? ""

        Diagnostics.record(status: code, body: body)

        if code == 401 || code == 403 { throw UsageAPIError.unauthorised }
        if code == 429 {
            let header = http?.value(forHTTPHeaderField: "Retry-After")
            throw UsageAPIError.rateLimited(retryAfter: header.flatMap(TimeInterval.init))
        }
        guard (200..<300).contains(code) else { throw UsageAPIError.http(code, body) }
        guard var usage = UsageReader.parse(data) else { throw UsageAPIError.unreadable(body) }

        usage.fetchedAt = Date()
        if usage.plan == nil { usage.plan = try? credentials().subscription }
        return usage
    }
}
