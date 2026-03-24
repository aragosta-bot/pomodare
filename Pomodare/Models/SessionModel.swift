import Foundation
import Observation
import SwiftUI

enum AppScreen: Equatable {
    case home
    case waiting
    case countdown(count: Int)
    case session
    case result
}

@Observable
class SessionModel {
    // MARK: - Navigation
    var screen: AppScreen = .home

    // MARK: - Session Info
    var sessionCode: String = ""
    var isHost: Bool = false
    var durationMinutes: Int = 25
    var sessionStatus: String = "waiting"

    // MARK: - Players
    var playerId: String
    var partnerConnected: Bool = false

    // MARK: - Times
    var myActiveSeconds: Int = 0
    var partnerActiveSeconds: Int = 0
    var sessionStartedAt: Date?

    // MARK: - Activity State
    var isIdle: Bool = false
    var sessionActive: Bool = false

    // MARK: - Error
    var errorMessage: String? = nil
    var isLoading: Bool = false

    // MARK: - Menu Bar Icon
    var menuBarIconName: String {
        "circle.fill"
    }

    var menuBarColor: Color {
        guard sessionActive else { return Color(hex: "#888888") }
        return isIdle ? Color(hex: "#ef4444") : Color(hex: "#10b981")
    }

    // MARK: - Computed
    var totalDurationSeconds: Int { durationMinutes * 60 }

    var myProgress: Double {
        guard totalDurationSeconds > 0 else { return 0 }
        return min(Double(myActiveSeconds) / Double(totalDurationSeconds), 1.0)
    }

    var partnerProgress: Double {
        guard totalDurationSeconds > 0 else { return 0 }
        return min(Double(partnerActiveSeconds) / Double(totalDurationSeconds), 1.0)
    }

    var timeRemaining: Int {
        guard let start = sessionStartedAt else { return totalDurationSeconds }
        let elapsed = Int(Date().timeIntervalSince(start))
        return max(0, totalDurationSeconds - elapsed)
    }

    var winner: String {
        if myActiveSeconds > partnerActiveSeconds { return "You" }
        if partnerActiveSeconds > myActiveSeconds { return "Partner" }
        return "Tie"
    }

    // MARK: - Dependencies
    let activityTracker = ActivityTracker()
    let supabase = SupabaseClient()

    // MARK: - Tasks
    private var pollTask: Task<Void, Never>?
    private var updateTask: Task<Void, Never>?
    private var countdownTask: Task<Void, Never>?
    private var sessionTimerTask: Task<Void, Never>?

    // MARK: - Init
    init() {
        if let id = UserDefaults.standard.string(forKey: "focusduel.playerId") {
            self.playerId = id
        } else {
            let id = UUID().uuidString
            UserDefaults.standard.set(id, forKey: "focusduel.playerId")
            self.playerId = id
        }
    }

    // MARK: - Create Session
    func createSession() {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        let code = Self.randomCode()

        Task { @MainActor in
            do {
                try await supabase.createSession(id: code, player1Id: playerId, durationMinutes: durationMinutes)
                self.sessionCode = code
                self.isHost = true
                self.screen = .waiting
                self.startPolling()
            } catch {
                self.errorMessage = error.localizedDescription
            }
            self.isLoading = false
        }
    }

    // MARK: - Join Session
    func joinSession(code: String) {
        guard !isLoading else { return }
        guard code.count == 4 else {
            errorMessage = "Code must be 4 letters"
            return
        }

        isLoading = true
        errorMessage = nil
        let upperCode = code.uppercased()

        Task { @MainActor in
            do {
                let session = try await supabase.joinSession(id: upperCode, player2Id: playerId)
                self.sessionCode = upperCode
                self.isHost = false
                self.durationMinutes = session.durationMinutes
                self.screen = .waiting
                self.startPolling()
            } catch {
                self.errorMessage = "Session not found or already started"
            }
            self.isLoading = false
        }
    }

    // MARK: - Leave / Reset
    func leaveSession() {
        pollTask?.cancel()
        updateTask?.cancel()
        countdownTask?.cancel()
        sessionTimerTask?.cancel()
        activityTracker.stop()

        sessionCode = ""
        isHost = false
        partnerConnected = false
        myActiveSeconds = 0
        partnerActiveSeconds = 0
        sessionStartedAt = nil
        sessionActive = false
        isIdle = false
        sessionStatus = "waiting"
        errorMessage = nil
        screen = .home
    }

    // MARK: - Polling
    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { @MainActor in
            while !Task.isCancelled {
                await self.pollSession()
                try? await Task.sleep(nanoseconds: 10_000_000_000) // 10s
            }
        }
    }

    private func pollSession() async {
        guard !sessionCode.isEmpty else { return }
        do {
            let session = try await supabase.fetchSession(id: sessionCode)
            await MainActor.run { handleSessionUpdate(session) }
        } catch {
            // Silently ignore poll errors
        }
    }

    @MainActor
    private func handleSessionUpdate(_ session: SessionData) {
        let prevStatus = sessionStatus
        sessionStatus = session.status
        durationMinutes = session.durationMinutes

        // Check partner connection
        if isHost {
            partnerConnected = session.player2Id != nil && !session.player2Id!.isEmpty
        } else {
            partnerConnected = true // if we joined, host is already there
        }

        // Update partner's active seconds
        if isHost {
            partnerActiveSeconds = session.player2ActiveSeconds
        } else {
            partnerActiveSeconds = session.player1ActiveSeconds
        }
        if isHost {
            myActiveSeconds = max(myActiveSeconds, session.player1ActiveSeconds)
        } else {
            myActiveSeconds = max(myActiveSeconds, session.player2ActiveSeconds)
        }

        // Transition: waiting → active
        if prevStatus != "active" && session.status == "active" {
            if let startedAt = session.startedAt {
                self.sessionStartedAt = startedAt
            }
            beginSession()
        }

        // Both connected on host side → trigger start
        if screen == .waiting && isHost && partnerConnected && session.status == "waiting" {
            triggerStart()
        }

        // Session finished
        if session.status == "finished" && screen == .session {
            endSession()
        }
    }

    private func triggerStart() {
        guard isHost else { return }
        Task { @MainActor in
            do {
                try await self.supabase.startSession(id: self.sessionCode)
            } catch {
                // ignore
            }
        }
    }

    private func beginSession() {
        pollTask?.cancel()
        countdownTask = Task { @MainActor in
            for i in stride(from: 3, through: 1, by: -1) {
                self.screen = .countdown(count: i)
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            self.screen = .session
            self.sessionActive = true
            self.startActivityTracking()
            self.startUpdateLoop()
            self.startSessionTimer()
            self.startPolling()
        }
    }

    private func startActivityTracking() {
        activityTracker.onIdleChanged = { [weak self] idle in
            Task { @MainActor in
                self?.isIdle = idle
            }
        }
        activityTracker.start()
    }

    private func startUpdateLoop() {
        updateTask?.cancel()
        updateTask = Task { @MainActor in
            while !Task.isCancelled && self.sessionActive {
                try? await Task.sleep(nanoseconds: 10_000_000_000) // 10s
                guard self.sessionActive else { break }
                let seconds = self.activityTracker.activeSeconds
                let isPlayer1 = self.isHost
                do {
                    try await self.supabase.updateActiveSeconds(
                        sessionId: self.sessionCode,
                        isPlayer1: isPlayer1,
                        seconds: seconds
                    )
                } catch {
                    // ignore
                }
            }
        }
    }

    private func startSessionTimer() {
        sessionTimerTask?.cancel()
        sessionTimerTask = Task { @MainActor in
            while !Task.isCancelled && self.sessionActive {
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1s tick
                if self.timeRemaining <= 0 {
                    self.finishSession()
                    break
                }
            }
        }
    }

    private func finishSession() {
        sessionActive = false
        activityTracker.stop()
        updateTask?.cancel()

        // Final update
        Task { @MainActor in
            let seconds = self.activityTracker.activeSeconds
            try? await self.supabase.updateActiveSeconds(
                sessionId: self.sessionCode,
                isPlayer1: self.isHost,
                seconds: seconds
            )
            if self.isHost {
                try? await self.supabase.finishSession(id: self.sessionCode)
            }
        }

        screen = .result
    }

    private func endSession() {
        sessionActive = false
        activityTracker.stop()
        updateTask?.cancel()
        screen = .result
    }

    // MARK: - Helpers
    static func randomCode() -> String {
        let letters = "ABCDEFGHJKLMNPQRSTUVWXYZ"
        return String((0..<4).compactMap { _ in letters.randomElement() })
    }
}
