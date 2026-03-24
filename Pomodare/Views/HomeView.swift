import SwiftUI

struct HomeView: View {
    @Environment(SessionModel.self) var model
    @State private var joinCode: String = ""
    @State private var selectedDuration: Int = 25

    private let durations = [25, 50, 90]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 6) {
                Text("⚡ Pomodare")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Compete to stay focused")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(hex: "#888888"))
            }
            .padding(.top, 28)
            .padding(.bottom, 24)

            // Duration picker
            VStack(alignment: .leading, spacing: 8) {
                Text("SESSION LENGTH")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color(hex: "#555555"))
                    .tracking(1)

                HStack(spacing: 8) {
                    ForEach(durations, id: \.self) { duration in
                        DurationButton(
                            minutes: duration,
                            isSelected: model.durationMinutes == duration
                        ) {
                            model.durationMinutes = duration
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.bottom, 20)

            // Create button
            VStack(spacing: 8) {
                Button {
                    model.createSession()
                } label: {
                    HStack {
                        if model.isLoading {
                            ProgressView()
                                .scaleEffect(0.7)
                                .tint(.white)
                        } else {
                            Image(systemName: "plus.circle.fill")
                        }
                        Text("Create Session")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .background(Color(hex: "#10b981"))
                    .foregroundStyle(.white)
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
                .disabled(model.isLoading)
            }
            .padding(.horizontal, 20)

            // Divider
            HStack {
                Rectangle().fill(Color(hex: "#2a2a2a")).frame(height: 1)
                Text("or")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(hex: "#555555"))
                    .padding(.horizontal, 8)
                Rectangle().fill(Color(hex: "#2a2a2a")).frame(height: 1)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            // Join section
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    TextField("Enter code (e.g. WOLF)", text: $joinCode)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color(hex: "#252525"))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color(hex: "#333333"), lineWidth: 1)
                        )
                        .onChange(of: joinCode) { _, new in
                            joinCode = String(new.uppercased().prefix(4))
                        }
                        .onSubmit {
                            model.joinSession(code: joinCode)
                        }

                    Button {
                        model.joinSession(code: joinCode)
                    } label: {
                        Text("Join")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .frame(height: 40)
                            .background(Color(hex: "#2a2a2a"))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color(hex: "#444444"), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(joinCode.count < 4 || model.isLoading)
                    .opacity(joinCode.count < 4 ? 0.4 : 1)
                }
            }
            .padding(.horizontal, 20)

            // Error
            if let error = model.errorMessage {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(hex: "#ef4444"))
                    .padding(.top, 10)
                    .padding(.horizontal, 20)
            }

            Spacer(minLength: 24)
        }
        .frame(width: 280)
    }
}

struct DurationButton: View {
    let minutes: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("\(minutes)m")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isSelected ? .white : Color(hex: "#666666"))
                .frame(height: 30)
                .frame(maxWidth: .infinity)
                .background(isSelected ? Color(hex: "#10b981") : Color(hex: "#252525"))
                .cornerRadius(7)
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(isSelected ? Color.clear : Color(hex: "#333333"), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}
