import SwiftUI

// MARK: - FilledButtonStyle

struct FilledButtonStyle: ButtonStyle {
    var color: Color = .pomAccent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .background(configuration.isPressed ? color.opacity(0.8) : color)
            .foregroundStyle(.white)
            .font(.subheadline.weight(.semibold))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - OutlineButtonStyle

struct OutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .background(.clear)
            .foregroundStyle(Color.pomMuted)
            .font(.subheadline)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.pomBorder, lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - IconButtonStyle

struct IconButtonStyle: ButtonStyle {
    var isDisabled: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 36, height: 36)
            .background(Color.pomSurface)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .opacity(isDisabled ? 0.4 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
