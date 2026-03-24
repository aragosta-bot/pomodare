import SwiftUI

struct CountdownView: View {
    let count: Int

    var body: some View {
        VStack(spacing: 16) {
            Text("Get Ready")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color(hex: "#888888"))

            Text("\(count)")
                .font(.system(size: 80, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .contentTransition(.numericText(countsDown: true))
                .animation(.spring(duration: 0.4), value: count)
        }
        .frame(width: 280, height: 320)
    }
}

struct SessionView: View {
    @Environment(SessionModel.self) var model
    @State private var tick = 0

    var body: some View {
        VStack(spacing: 0) {
            // Top bar: status + timer
            HStack {
                // Activity indicator
                HStack(spacing: 5) {
                    Circle()
                        .fill(model.isIdle ? Color(hex: "#ef4444") : Color(hex: "#10b981"))
                        .frame(width: 8, height: 8)
                    Text(model.isIdle ? "Idle" : "Active")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(model.isIdle ? Color(hex: "#ef4444") : Color(hex: "#10b981"))
                }

                Spacer()

                // Session timer
                Text(formatTime(model.timeRemaining))
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(model.timeRemaining < 60 ? Color(hex: "#ef4444") : Color(hex: "#888888"))
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 20)

            // Progress bars
            VStack(spacing: 16) {
                PlayerProgressRow(
                    label: "You",
                    seconds: model.myActiveSeconds,
                    progress: model.myProgress,
                    color: Color(hex: "#10b981"),
                    isIdle: model.isIdle
                )

                PlayerProgressRow(
                    label: "Partner",
                    seconds: model.partnerActiveSeconds,
                    progress: model.partnerProgress,
                    color: Color(hex: "#3b82f6"),
                    isIdle: false
                )
            }
            .padding(.horizontal, 20)

            Spacer()

            // Session code
            HStack {
                Text("Session:")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(hex: "#555555"))
                Text(model.sessionCode)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color(hex: "#666666"))
            }
            .padding(.bottom, 20)
        }
        .frame(width: 280, height: 280)
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            tick += 1
        }
    }

    private func formatTime(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}

struct PlayerProgressRow: View {
    let label: String
    let seconds: Int
    let progress: Double
    let color: Color
    let isIdle: Bool

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                HStack(spacing: 6) {
                    if isIdle {
                        Image(systemName: "zzz")
                            .font(.system(size: 10))
                            .foregroundStyle(Color(hex: "#ef4444"))
                    }
                    Text(label)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isIdle ? Color(hex: "#ef4444") : .white)
                }

                Spacer()

                Text(formatActiveTime(seconds))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color(hex: "#888888"))
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(hex: "#252525"))
                        .frame(height: 8)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(isIdle ? Color(hex: "#ef4444") : color)
                        .frame(width: max(8, geo.size.width * progress), height: 8)
                        .animation(.linear(duration: 1), value: progress)
                }
            }
            .frame(height: 8)
        }
    }

    private func formatActiveTime(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}
