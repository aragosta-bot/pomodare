import SwiftUI

// MARK: - MenuBarView (Router)

struct MenuBarView: View {

    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            switch appState.phase {
            case .idle:
                JoinView()
            case .waiting:
                WaitingView()
            case .lobby, .active, .breakTime, .roundResult:
                SessionView()
            case .finished:
                ResultView()
            }
        }
        .frame(width: 280)
        .padding(16)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// MARK: - Screen 1: JoinView

private struct JoinView: View {

    @Environment(AppState.self) private var appState
    @State private var joinCode = ""
    @State private var isCreating = false
    @State private var isJoining = false
    @State private var opacity: Double = 0
    @State private var shakeOffset: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pomodare 🍅")
                .font(.title2.bold())
                .foregroundStyle(.primary)

            HStack(spacing: 8) {
                // Nowa sesja
                Button("Nowa sesja") {
                    createSession()
                }
                .buttonStyle(FilledButtonStyle())
                .disabled(isCreating)

                Spacer()

                // Code field
                TextField("XXXX", text: $joinCode)
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .frame(width: 60, height: 36)
                    .background(Color.pomSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.pomBorder, lineWidth: 1)
                    )
                    .foregroundStyle(.primary)
                    .onChange(of: joinCode) { _, new in
                        joinCode = String(
                            new.uppercased()
                                .filter(\.isLetter)
                                .prefix(4)
                        )
                    }
                    .offset(x: shakeOffset)

                // Join arrow
                Button {
                    joinSession()
                } label: {
                    Image(systemName: "arrow.right")
                        .foregroundStyle(joinCode.isEmpty ? Color.pomMuted : Color.pomAccent)
                }
                .buttonStyle(IconButtonStyle(isDisabled: joinCode.isEmpty))
                .disabled(joinCode.isEmpty || isJoining)
            }

            if let error = appState.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .opacity(opacity)
        .onAppear {
            withAnimation(.easeOut(duration: 0.2)) {
                opacity = 1
            }
        }
    }

    // MARK: - Actions

    private func createSession() {
        isCreating = true
        let code = randomCode()
        let hostUUID = UUID()
        Task {
            do {
                let row = try await SupabaseService.shared.createSession(id: code, hostUUID: hostUUID)
                await MainActor.run {
                    appState.session = Session(
                        id: row.id,
                        hostUUID: hostUUID,
                        guestUUID: nil,
                        state: .waiting,
                        roundNumber: row.roundNumber,
                        timerStartedAt: nil,
                        phaseDurationSec: row.phaseDurationSec,
                        totalRounds: row.totalRounds
                    )
                    appState.localParticipant = Participant(
                        id: UUID(),
                        sessionId: code,
                        userUUID: hostUUID,
                        role: "host",
                        committed: false,
                        gaveUp: false,
                        roundsWon: 0,
                        lastSeenAt: Date()
                    )
                    appState.phase = .waiting
                    isCreating = false
                    startPolling(sessionId: code, localUUID: hostUUID)
                }
            } catch {
                await MainActor.run {
                    appState.errorMessage = error.localizedDescription
                    isCreating = false
                }
            }
        }
    }

    private func joinSession() {
        guard joinCode.count == 4 else {
            triggerShake()
            return
        }
        isJoining = true
        let guestUUID = UUID()
        Task {
            do {
                let row = try await SupabaseService.shared.joinSession(id: joinCode, guestUUID: guestUUID)
                await MainActor.run {
                    appState.session = Session(
                        id: row.id,
                        hostUUID: UUID(uuidString: row.hostUUID) ?? UUID(),
                        guestUUID: guestUUID,
                        state: SessionPhase(rawValue: row.state) ?? .lobby,
                        roundNumber: row.roundNumber,
                        timerStartedAt: nil,
                        phaseDurationSec: row.phaseDurationSec,
                        totalRounds: row.totalRounds
                    )
                    appState.localParticipant = Participant(
                        id: UUID(),
                        sessionId: joinCode,
                        userUUID: guestUUID,
                        role: "guest",
                        committed: false,
                        gaveUp: false,
                        roundsWon: 0,
                        lastSeenAt: Date()
                    )
                    appState.phase = .lobby
                    isJoining = false
                    startPolling(sessionId: joinCode, localUUID: guestUUID)
                }
            } catch {
                await MainActor.run {
                    appState.errorMessage = error.localizedDescription
                    isJoining = false
                    triggerShake()
                }
            }
        }
    }

    private func triggerShake() {
        let keyframes: [(CGFloat, Double)] = [
            (8, 0.05), (-8, 0.05), (6, 0.05),
            (-6, 0.05), (4, 0.05), (0, 0.05)
        ]
        var delay = 0.0
        for (offset, duration) in keyframes {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.easeInOut(duration: duration)) {
                    shakeOffset = offset
                }
            }
            delay += duration
        }
    }

    private func startPolling(sessionId: String, localUUID: UUID) {
        SupabaseService.shared.subscribeToSession(id: sessionId) { sessionRow, participants in
            applyRemoteUpdate(sessionRow: sessionRow, participants: participants, localUUID: localUUID)
        }
    }

    private func applyRemoteUpdate(sessionRow: SessionRow, participants: [ParticipantRow], localUUID: UUID) {
        guard var session = appState.session else { return }
        let newPhase = SessionPhase(rawValue: sessionRow.state) ?? appState.phase

        session.state = newPhase
        session.roundNumber = sessionRow.roundNumber
        appState.session = session

        if newPhase != appState.phase {
            appState.phase = newPhase
            if newPhase == .active {
                appState.startCountdown(from: sessionRow.phaseDurationSec)
            }
        }

        let remote = participants.first { $0.userUUID != localUUID.uuidString }
        if let r = remote {
            appState.remoteParticipant = Participant(
                id: UUID(uuidString: r.id) ?? UUID(),
                sessionId: r.sessionId,
                userUUID: UUID(uuidString: r.userUUID) ?? UUID(),
                role: r.role,
                committed: r.committed,
                gaveUp: r.gaveUp,
                roundsWon: r.roundsWon,
                lastSeenAt: ISO8601DateFormatter().date(from: r.lastSeenAt) ?? Date()
            )
        }
    }

    private func randomCode() -> String {
        let letters = "ABCDEFGHJKLMNPQRSTUVWXYZ"
        return String((0..<4).compactMap { _ in letters.randomElement() })
    }
}

// MARK: - Screen 2: WaitingView

private struct WaitingView: View {

    @Environment(AppState.self) private var appState
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            // Section label
            Text("KOD SESJI")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.pomMuted)

            // Code card
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.pomSurface)

                HStack {
                    Text(appState.sessionCode)
                        .font(.system(size: 34, weight: .bold, design: .monospaced))
                        .kerning(8)
                        .foregroundStyle(.primary)

                    Spacer()

                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(appState.sessionCode, forType: .string)
                        withAnimation { copied = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            withAnimation { copied = false }
                        }
                    } label: {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .foregroundStyle(copied ? Color.pomSuccess : Color.pomMuted)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Skopiuj kod sesji")
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .frame(height: 72)

            // Spinner + waiting label
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.8)
                    .frame(width: 18)
                Text("Czekam na partnera...")
                    .font(.subheadline)
                    .foregroundStyle(Color.pomMuted)
            }

            // Cancel button
            Button("Anuluj") {
                appState.reset()
            }
            .buttonStyle(OutlineButtonStyle())
            .accessibilityLabel("Anuluj sesję")
        }
    }
}

// MARK: - Screen 3: SessionView

private struct SessionView: View {

    @Environment(AppState.self) private var appState
    @State private var pulseScale: CGFloat = 1.0

    private var progress: Double {
        guard let session = appState.session, session.phaseDurationSec > 0 else { return 0 }
        return Double(appState.remainingSeconds) / Double(session.phaseDurationSec)
    }

    private var isBreak: Bool { appState.phase == .breakTime }

    var body: some View {
        VStack(spacing: 12) {

            // Header
            HStack {
                if let session = appState.session {
                    Text("🍅 Runda \(session.roundNumber + 1)/\(session.totalRounds)")
                        .font(.subheadline.weight(.semibold))
                } else {
                    Text("🍅 Sesja")
                        .font(.subheadline.weight(.semibold))
                }
                Spacer()
                Button {
                    // settings placeholder
                } label: {
                    Image(systemName: "gearshape")
                        .foregroundStyle(Color.pomMuted)
                }
                .buttonStyle(.plain)
            }

            // Timer ring
            ZStack {
                // Background ring
                Circle()
                    .stroke(Color.pomBorder, lineWidth: 10)

                // Progress ring
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        isBreak ? Color.blue.opacity(0.7) : Color.pomAccent,
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: progress)

                // Time label
                Text(appState.formattedRemaining)
                    .font(.system(size: 38, weight: .bold, design: .monospaced))
                    .foregroundStyle(.primary)
            }
            .frame(width: 160, height: 160)
            .padding(.vertical, 4)

            // Commit button (conditional)
            commitSection

            Divider()
                .background(Color.pomBorder)

            // Partner status
            partnerStatus
        }
    }

    // MARK: - Commit section

    @ViewBuilder
    private var commitSection: some View {
        let committed = appState.localParticipant?.committed ?? false
        let elapsed = elapsedSeconds
        let totalDuration = appState.session?.phaseDurationSec ?? 1500

        if isBreak {
            EmptyView()
        } else if committed {
            // Committed state
            Button {} label: {
                Text("✅ Zadeklarowano")
            }
            .buttonStyle(OutlineButtonStyle())
            .disabled(true)
        } else if elapsed > (totalDuration - 5 * 60) {
            // Locked (after 20 min if 25 min round, i.e. only first 5 min available)
            Text("🔒 Runda zablokowana")
                .font(.subheadline.italic())
                .foregroundStyle(Color.pomMuted)
                .frame(maxWidth: .infinity, alignment: .center)
        } else {
            // Available — pulse animation
            Button {
                commitToWorking()
            } label: {
                Text("🍅 Pracuję")
            }
            .buttonStyle(FilledButtonStyle(color: .pomSuccess))
            .scaleEffect(pulseScale)
            .onAppear { startPulse() }
            .onDisappear { pulseScale = 1.0 }
        }
    }

    // MARK: - Partner status

    private var partnerStatus: some View {
        HStack(spacing: 4) {
            Text("Partner: ")
                .font(.caption)
                .foregroundStyle(Color.pomMuted)

            if let remote = appState.remoteParticipant {
                if remote.isOnline {
                    if remote.committed {
                        Text("✅ pracuje")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.pomSuccess)
                    } else {
                        Text("⏳ nie zadeklarował")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.pomWarning)
                    }
                } else {
                    Text("⚠️ offline")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.red)
                }
            } else {
                Text("⏳ oczekiwanie...")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.pomMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Helpers

    private var elapsedSeconds: Int {
        guard let session = appState.session else { return 0 }
        return session.phaseDurationSec - appState.remainingSeconds
    }

    private func startPulse() {
        withAnimation(
            .easeInOut(duration: 1.2)
            .repeatForever(autoreverses: true)
        ) {
            pulseScale = 1.02
        }
    }

    private func commitToWorking() {
        guard let session = appState.session,
              let local = appState.localParticipant else { return }
        Task {
            try? await SupabaseService.shared.updateParticipant(
                sessionId: session.id,
                userUUID: local.userUUID,
                committed: true
            )
        }
        appState.localParticipant?.committed = true
    }
}

// MARK: - Screen 4: ResultView

private struct ResultView: View {

    @Environment(AppState.self) private var appState
    @State private var cardOffset: CGFloat = -30
    @State private var cardOpacity: Double = 0

    private var localWins: Int { appState.localParticipant?.roundsWon ?? 0 }
    private var remoteWins: Int { appState.remoteParticipant?.roundsWon ?? 0 }

    private var verdictText: String {
        if localWins > remoteWins {
            let diff = localWins - remoteWins
            return "Wygrałeś o \(diff) \(diff == 1 ? "rundę" : "rundy")! 🔥"
        } else if localWins < remoteWins {
            let diff = remoteWins - localWins
            return "Przegrałeś o \(diff) \(diff == 1 ? "rundę" : "rundy") 😤"
        } else {
            return "Remis! Dobrze tak trzymać 🤝"
        }
    }

    private var verdictColor: Color {
        if localWins > remoteWins { return .pomSuccess }
        if localWins < remoteWins { return .pomMuted }
        return .pomAccent
    }

    var body: some View {
        VStack(spacing: 12) {

            Text("Sesja zakończona 🎉")
                .font(.title3.bold())
                .frame(maxWidth: .infinity, alignment: .center)

            // Comparison card
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.pomSurface)

                HStack(spacing: 0) {
                    // Local (Ty)
                    VStack(spacing: 4) {
                        HStack(spacing: 4) {
                            Text("\(localWins)")
                                .font(.system(size: 32, weight: .bold))
                            if localWins > remoteWins {
                                Image(systemName: "trophy.fill")
                                    .foregroundStyle(Color.pomWarning)
                            }
                        }
                        Text("Ty")
                            .font(.caption)
                            .foregroundStyle(Color.pomMuted)
                    }
                    .frame(maxWidth: .infinity)

                    Divider()
                        .frame(height: 50)

                    // Remote (Partner)
                    VStack(spacing: 4) {
                        HStack(spacing: 4) {
                            Text("\(remoteWins)")
                                .font(.system(size: 32, weight: .bold))
                            if remoteWins > localWins {
                                Image(systemName: "trophy.fill")
                                    .foregroundStyle(Color.pomWarning)
                            }
                        }
                        Text("Partner")
                            .font(.caption)
                            .foregroundStyle(Color.pomMuted)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.vertical, 16)
                .padding(.horizontal, 20)
            }
            .offset(y: cardOffset)
            .opacity(cardOpacity)
            .onAppear {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    cardOffset = 0
                    cardOpacity = 1
                }
            }

            // Verdict
            Text(verdictText)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(verdictColor)
                .frame(maxWidth: .infinity, alignment: .center)

            // CTA
            Button("Nowa sesja") {
                appState.reset()
            }
            .buttonStyle(FilledButtonStyle())
            .accessibilityLabel("Rozpocznij nową sesję")
        }
    }
}
