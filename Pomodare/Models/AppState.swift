import Foundation
import Observation

// MARK: - Session Phase

enum SessionPhase: String, Equatable {
    /// No active session — home screen
    case idle
    /// Session created, waiting for guest to join
    case waiting
    /// Both players connected, about to start a round
    case lobby
    /// Active focus round — timer counting down
    case active
    /// Short break between rounds
    case breakTime
    /// Round ended — showing who committed / gave up
    case roundResult
    /// All rounds done — final scoreboard
    case finished
}

// MARK: - Participant

struct Participant: Identifiable, Equatable {
    let id: UUID
    let sessionId: String
    let userUUID: UUID
    let role: String          // "host" | "guest"
    var committed: Bool
    var gaveUp: Bool
    var roundsWon: Int
    var lastSeenAt: Date

    var isOnline: Bool {
        Date().timeIntervalSince(lastSeenAt) < 10
    }
}

// MARK: - Session

struct Session: Equatable {
    let id: String            // 4-letter code e.g. "BRAT"
    let hostUUID: UUID
    var guestUUID: UUID?
    var state: SessionPhase
    var roundNumber: Int
    var timerStartedAt: Date?
    var phaseDurationSec: Int
    var totalRounds: Int
}

// MARK: - AppState

@Observable
final class AppState {

    // MARK: Session data
    var session: Session?
    var localParticipant: Participant?
    var remoteParticipant: Participant?

    // MARK: UI
    var phase: SessionPhase = .idle
    var errorMessage: String?

    // MARK: Timer
    private(set) var remainingSeconds: Int = 25 * 60
    private var timerTask: Task<Void, Never>?

    // MARK: Derived helpers

    var sessionCode: String { session?.id ?? "" }

    var partnerStatus: String {
        guard let remote = remoteParticipant else { return "waiting..." }
        if remote.isOnline {
            return remote.committed ? "🍅 working" : "connected"
        }
        return "offline"
    }

    var formattedRemaining: String {
        let m = remainingSeconds / 60
        let s = remainingSeconds % 60
        return String(format: "%02d:%02d", m, s)
    }

    // MARK: - Timer control

    func startCountdown(from seconds: Int) {
        remainingSeconds = seconds
        stopCountdown()
        timerTask = Task { @MainActor in
            while remainingSeconds > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                remainingSeconds -= 1
            }
            // Round ended
            if phase == .active {
                phase = .roundResult
            }
        }
    }

    func stopCountdown() {
        timerTask?.cancel()
        timerTask = nil
    }

    // MARK: - State transitions

    func reset() {
        stopCountdown()
        session = nil
        localParticipant = nil
        remoteParticipant = nil
        phase = .idle
        remainingSeconds = 25 * 60
        errorMessage = nil
    }
}
