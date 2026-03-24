import SwiftUI

struct WaitingView: View {
    @Environment(SessionModel.self) var model

    var body: some View {
        VStack(spacing: 0) {
            // Back button
            HStack {
                Button {
                    model.leaveSession()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .medium))
                        Text("Back")
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(Color(hex: "#666666"))
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            Spacer()

            // Code display
            VStack(spacing: 16) {
                Text("Share this code")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(hex: "#888888"))

                Text(model.sessionCode)
                    .font(.system(size: 44, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .tracking(8)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                    .background(Color(hex: "#252525"))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(hex: "#333333"), lineWidth: 1)
                    )

                Button {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(model.sessionCode, forType: .string)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 11))
                        Text("Copy code")
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(Color(hex: "#555555"))
                }
                .buttonStyle(.plain)
            }

            Spacer()

            // Partner status
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    if model.partnerConnected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color(hex: "#10b981"))
                        Text("Partner connected!")
                            .foregroundStyle(Color(hex: "#10b981"))
                    } else {
                        ProgressView()
                            .scaleEffect(0.6)
                            .tint(Color(hex: "#666666"))
                        Text("Waiting for partner...")
                            .foregroundStyle(Color(hex: "#666666"))
                    }
                }
                .font(.system(size: 13, weight: .medium))

                if model.partnerConnected {
                    Text("Starting shortly...")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(hex: "#555555"))
                }
            }
            .padding(.bottom, 32)
        }
        .frame(width: 280, height: 320)
    }
}
