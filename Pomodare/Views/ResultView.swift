import SwiftUI

struct ResultView: View {
    @Environment(SessionModel.self) var model

    private var myTime: Int { model.myActiveSeconds }
    private var partnerTime: Int { model.partnerActiveSeconds }
    private var winner: String { model.winner }

    var body: some View {
        VStack(spacing: 0) {
            // Winner banner
            VStack(spacing: 8) {
                Text(winnerEmoji)
                    .font(.system(size: 36))

                Text(winnerTitle)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(winnerColor)

                Text(winnerSubtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Color(hex: "#888888"))
            }
            .padding(.top, 28)
            .padding(.bottom, 24)

            // Score comparison
            VStack(spacing: 12) {
                ResultScoreRow(
                    label: "You",
                    seconds: myTime,
                    total: model.totalDurationSeconds,
                    color: Color(hex: "#10b981"),
                    isWinner: winner == "You"
                )
                ResultScoreRow(
                    label: "Partner",
                    seconds: partnerTime,
                    total: model.totalDurationSeconds,
                    color: Color(hex: "#3b82f6"),
                    isWinner: winner == "Partner"
                )
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)

            // Rematch / Home buttons
            VStack(spacing: 8) {
                Button {
                    // Start a new session with same settings
                    model.leaveSession()
                    Task {
                        try? await Task.sleep(nanoseconds: 100_000_000)
                        await MainActor.run {
                            model.createSession()
                        }
                    }
                } label: {
                    HStack {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Rematch")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(Color(hex: "#10b981"))
                    .foregroundStyle(.white)
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)

                Button {
                    model.leaveSession()
                } label: {
                    Text("Back to Home")
                        .font(.system(size: 13))
                        .foregroundStyle(Color(hex: "#666666"))
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(Color(hex: "#252525"))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .frame(width: 280)
    }

    private var winnerEmoji: String {
        switch winner {
        case "You": return "🏆"
        case "Partner": return "😤"
        default: return "🤝"
        }
    }

    private var winnerTitle: String {
        switch winner {
        case "You": return "You Won!"
        case "Partner": return "Partner Won"
        default: return "It's a Tie!"
        }
    }

    private var winnerSubtitle: String {
        switch winner {
        case "You": return "Nice work, focus champion 💪"
        case "Partner": return "Get them next time"
        default: return "Equally matched!"
        }
    }

    private var winnerColor: Color {
        switch winner {
        case "You": return Color(hex: "#10b981")
        case "Partner": return Color(hex: "#ef4444")
        default: return Color(hex: "#f59e0b")
        }
    }
}

struct ResultScoreRow: View {
    let label: String
    let seconds: Int
    let total: Int
    let color: Color
    let isWinner: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Label + badge
            HStack(spacing: 6) {
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 54, alignment: .leading)
                if isWinner {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Color(hex: "#f59e0b"))
                }
            }
            .frame(width: 72, alignment: .leading)

            // Progress bar
            GeometryReader { geo in
                let w = total > 0 ? geo.size.width * Double(seconds) / Double(total) : 0
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(hex: "#252525"))
                        .frame(height: 8)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isWinner ? Color(hex: "#f59e0b") : color)
                        .frame(width: max(8, w), height: 8)
                }
            }
            .frame(height: 8)

            // Time
            Text(formatTime(seconds))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(Color(hex: "#888888"))
                .frame(width: 40, alignment: .trailing)
        }
    }

    private func formatTime(_ s: Int) -> String {
        let m = s / 60
        let sec = s % 60
        return String(format: "%d:%02d", m, sec)
    }
}
