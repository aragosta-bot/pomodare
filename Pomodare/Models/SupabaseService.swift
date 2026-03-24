import Foundation

// MARK: - SupabaseService
//
// Pure URLSession REST client — no third-party SDK.
// Realtime fallback: polls every 3 seconds via `subscribeToSession`.

final class SupabaseService {

    // MARK: - Configuration

    static let shared = SupabaseService()

    private var baseURL: URL {
        let raw = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String ?? ""
        return URL(string: raw)!
    }

    private var anonKey: String {
        Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String ?? ""
    }

    private var headers: [String: String] {
        [
            "apikey": anonKey,
            "Authorization": "Bearer \(anonKey)",
            "Content-Type": "application/json",
            "Prefer": "return=representation"
        ]
    }

    // MARK: - Polling

    private var pollTask: Task<Void, Never>?

    // MARK: - Session API

    /// Create a new session. Returns the created Session row.
    func createSession(id: String, hostUUID: UUID, phaseDurationSec: Int = 1500, totalRounds: Int = 5) async throws -> SessionRow {
        let body: [String: Any] = [
            "id": id,
            "host_uuid": hostUUID.uuidString,
            "state": "waiting",
            "phase_duration_sec": phaseDurationSec,
            "total_rounds": totalRounds
        ]
        let row: [SessionRow] = try await post(path: "sessions", body: body)
        guard let first = row.first else { throw SupabaseError.noData }

        // Insert host participant
        _ = try await insertParticipant(sessionId: id, userUUID: hostUUID, role: "host")

        return first
    }

    /// Join an existing session as guest. Returns the updated Session row.
    func joinSession(id: String, guestUUID: UUID) async throws -> SessionRow {
        // Update session with guest_uuid and transition to lobby
        let body: [String: Any] = [
            "guest_uuid": guestUUID.uuidString,
            "state": "lobby"
        ]
        let row: [SessionRow] = try await patch(path: "sessions?id=eq.\(id)", body: body)
        guard let first = row.first else { throw SupabaseError.noData }

        // Insert guest participant
        _ = try await insertParticipant(sessionId: id, userUUID: guestUUID, role: "guest")

        return first
    }

    /// Fetch current session state (used for polling).
    func fetchSession(id: String) async throws -> SessionRow {
        let rows: [SessionRow] = try await get(path: "sessions?id=eq.\(id)")
        guard let first = rows.first else { throw SupabaseError.sessionNotFound }
        return first
    }

    /// Fetch all participants for a session.
    func fetchParticipants(sessionId: String) async throws -> [ParticipantRow] {
        return try await get(path: "participants?session_id=eq.\(sessionId)")
    }

    /// Update local participant (committed, gave_up, last_seen_at).
    func updateParticipant(sessionId: String, userUUID: UUID, committed: Bool? = nil, gaveUp: Bool? = nil) async throws {
        var body: [String: Any] = [
            "last_seen_at": ISO8601DateFormatter().string(from: Date())
        ]
        if let committed { body["committed"] = committed }
        if let gaveUp    { body["gave_up"] = gaveUp }

        let _: [ParticipantRow] = try await patch(
            path: "participants?session_id=eq.\(sessionId)&user_uuid=eq.\(userUUID.uuidString)",
            body: body
        )
    }

    /// Update session state (host only).
    func updateSessionState(id: String, state: String, roundNumber: Int? = nil, timerStartedAt: Date? = nil) async throws {
        var body: [String: Any] = ["state": state]
        if let round = roundNumber      { body["round_number"] = round }
        if let started = timerStartedAt { body["timer_started_at"] = ISO8601DateFormatter().string(from: started) }

        let _: [SessionRow] = try await patch(path: "sessions?id=eq.\(id)", body: body)
    }

    // MARK: - Realtime Fallback (3s poll)

    /// Starts polling every 3 seconds. Calls `onChange` on each update.
    func subscribeToSession(id: String, onChange: @escaping (SessionRow, [ParticipantRow]) -> Void) {
        stopPolling()
        pollTask = Task {
            while !Task.isCancelled {
                do {
                    async let sessionFetch = fetchSession(id: id)
                    async let participantsFetch = fetchParticipants(sessionId: id)
                    let (session, participants) = try await (sessionFetch, participantsFetch)
                    await MainActor.run { onChange(session, participants) }
                } catch {
                    // Silently ignore transient errors during polling
                }
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    // MARK: - Private helpers

    private func insertParticipant(sessionId: String, userUUID: UUID, role: String) async throws -> ParticipantRow {
        let body: [String: Any] = [
            "session_id": sessionId,
            "user_uuid": userUUID.uuidString,
            "role": role
        ]
        let rows: [ParticipantRow] = try await post(path: "participants", body: body)
        guard let first = rows.first else { throw SupabaseError.noData }
        return first
    }

    private func get<T: Decodable>(path: String) async throws -> T {
        var request = URLRequest(url: baseURL.appendingPathComponent("rest/v1/\(path)"))
        request.httpMethod = "GET"
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response)
        return try JSONDecoder.supabase.decode(T.self, from: data)
    }

    private func post<T: Decodable>(path: String, body: [String: Any]) async throws -> T {
        var request = URLRequest(url: baseURL.appendingPathComponent("rest/v1/\(path)"))
        request.httpMethod = "POST"
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response)
        return try JSONDecoder.supabase.decode(T.self, from: data)
    }

    private func patch<T: Decodable>(path: String, body: [String: Any]) async throws -> T {
        let url = baseURL.appendingPathComponent("rest/v1/\(path)")
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response)
        return try JSONDecoder.supabase.decode(T.self, from: data)
    }

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw SupabaseError.httpError(code)
        }
    }
}

// MARK: - Data Transfer Objects

struct SessionRow: Codable {
    let id: String
    let hostUUID: String
    var guestUUID: String?
    var state: String
    var roundNumber: Int
    var timerStartedAt: String?
    var phaseDurationSec: Int
    var totalRounds: Int

    enum CodingKeys: String, CodingKey {
        case id
        case hostUUID = "host_uuid"
        case guestUUID = "guest_uuid"
        case state
        case roundNumber = "round_number"
        case timerStartedAt = "timer_started_at"
        case phaseDurationSec = "phase_duration_sec"
        case totalRounds = "total_rounds"
    }
}

struct ParticipantRow: Codable {
    let id: String
    let sessionId: String
    let userUUID: String
    let role: String
    var committed: Bool
    var gaveUp: Bool
    var roundsWon: Int
    var lastSeenAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case sessionId = "session_id"
        case userUUID = "user_uuid"
        case role
        case committed
        case gaveUp = "gave_up"
        case roundsWon = "rounds_won"
        case lastSeenAt = "last_seen_at"
    }
}

// MARK: - Errors

enum SupabaseError: LocalizedError {
    case noData
    case sessionNotFound
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .noData:            return "No data returned from Supabase."
        case .sessionNotFound:   return "Session not found. Check the code and try again."
        case .httpError(let c):  return "HTTP error \(c)."
        }
    }
}

// MARK: - JSONDecoder helper

private extension JSONDecoder {
    static var supabase: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
