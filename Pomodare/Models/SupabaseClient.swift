import Foundation

// TODO: Set your Supabase project URL and anon key here, or in Info.plist as SUPABASE_URL / SUPABASE_ANON_KEY
// See README.md for instructions.
private let SUPABASE_URL: String = {
    if let url = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String, !url.isEmpty { return url }
    return "https://YOUR_PROJECT.supabase.co"
}()

private let SUPABASE_ANON_KEY: String = {
    if let key = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String, !key.isEmpty { return key }
    return "YOUR_ANON_KEY"
}()

// MARK: - Data Models

struct SessionData: Decodable {
    let id: String
    let player1Id: String?
    let player2Id: String?
    let player1ActiveSeconds: Int
    let player2ActiveSeconds: Int
    let durationMinutes: Int
    let status: String
    let startedAt: Date?
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case player1Id = "player1_id"
        case player2Id = "player2_id"
        case player1ActiveSeconds = "player1_active_seconds"
        case player2ActiveSeconds = "player2_active_seconds"
        case durationMinutes = "duration_minutes"
        case status
        case startedAt = "started_at"
        case createdAt = "created_at"
    }
}

enum SupabaseError: Error, LocalizedError {
    case invalidURL
    case httpError(Int, String)
    case notFound
    case decodingError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .httpError(let code, let msg): return "HTTP \(code): \(msg)"
        case .notFound: return "Session not found"
        case .decodingError(let e): return "Decode error: \(e.localizedDescription)"
        }
    }
}

// MARK: - Client

final class SupabaseClient {
    private let baseURL: String
    private let anonKey: String
    private let urlSession: URLSession

    private lazy var decoder: JSONDecoder = {
        let d = JSONDecoder()
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let str = try container.decode(String.self)
            if let date = fmt.date(from: str) { return date }
            // Fallback without fractional seconds
            let fmt2 = ISO8601DateFormatter()
            if let date = fmt2.date(from: str) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode date: \(str)")
        }
        return d
    }()

    init() {
        self.baseURL = SUPABASE_URL
        self.anonKey = SUPABASE_ANON_KEY
        self.urlSession = URLSession.shared
    }

    // MARK: - Request Helpers

    private func request(
        path: String,
        method: String = "GET",
        body: [String: Any]? = nil,
        query: [String: String]? = nil,
        headers: [String: String] = [:]
    ) async throws -> Data {
        var urlStr = "\(baseURL)/rest/v1/\(path)"
        if let query = query, !query.isEmpty {
            let qs = query.map { k, v in "\(k)=\(v.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? v)" }.joined(separator: "&")
            urlStr += "?" + qs
        }
        guard let url = URL(string: urlStr) else { throw SupabaseError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("return=representation", forHTTPHeaderField: "Prefer")
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        if let body = body {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await urlSession.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw SupabaseError.httpError(http.statusCode, msg)
        }
        return data
    }

    // MARK: - Session Operations

    func createSession(id: String, player1Id: String, durationMinutes: Int) async throws {
        let body: [String: Any] = [
            "id": id,
            "player1_id": player1Id,
            "duration_minutes": durationMinutes,
            "status": "waiting"
        ]
        _ = try await request(path: "sessions", method: "POST", body: body)
    }

    func joinSession(id: String, player2Id: String) async throws -> SessionData {
        // First fetch to verify it exists and is waiting
        let session = try await fetchSession(id: id)
        guard session.status == "waiting" else {
            throw SupabaseError.httpError(409, "Session already started")
        }

        // Update player2_id
        let body: [String: Any] = ["player2_id": player2Id]
        let data = try await request(
            path: "sessions",
            method: "PATCH",
            body: body,
            query: ["id": "eq.\(id)"]
        )

        // Return the first updated row
        let sessions = try decodeArray(SessionData.self, from: data)
        guard let updated = sessions.first else { throw SupabaseError.notFound }
        return updated
    }

    func fetchSession(id: String) async throws -> SessionData {
        let data = try await request(
            path: "sessions",
            query: ["id": "eq.\(id)", "limit": "1"]
        )
        let sessions = try decodeArray(SessionData.self, from: data)
        guard let session = sessions.first else { throw SupabaseError.notFound }
        return session
    }

    func startSession(id: String) async throws {
        let now = ISO8601DateFormatter().string(from: Date())
        let body: [String: Any] = [
            "status": "active",
            "started_at": now
        ]
        _ = try await request(
            path: "sessions",
            method: "PATCH",
            body: body,
            query: ["id": "eq.\(id)"]
        )
    }

    func updateActiveSeconds(sessionId: String, isPlayer1: Bool, seconds: Int) async throws {
        let column = isPlayer1 ? "player1_active_seconds" : "player2_active_seconds"
        let body: [String: Any] = [column: seconds]
        _ = try await request(
            path: "sessions",
            method: "PATCH",
            body: body,
            query: ["id": "eq.\(sessionId)"]
        )
    }

    func finishSession(id: String) async throws {
        let body: [String: Any] = ["status": "finished"]
        _ = try await request(
            path: "sessions",
            method: "PATCH",
            body: body,
            query: ["id": "eq.\(id)"]
        )
    }

    // MARK: - Decoding Helpers

    private func decodeArray<T: Decodable>(_ type: T.Type, from data: Data) throws -> [T] {
        do {
            return try decoder.decode([T].self, from: data)
        } catch {
            throw SupabaseError.decodingError(error)
        }
    }
}
