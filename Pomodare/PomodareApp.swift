import SwiftUI

@main
struct PomodareApp: App {

    @State private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(appState)
        } label: {
            MenuBarLabel(phase: appState.phase)
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - MenuBarLabel

private struct MenuBarLabel: View {
    let phase: SessionPhase

    var body: some View {
        iconView
            .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var iconView: some View {
        switch phase {
        case .idle:
            Image(systemName: "circle")
                .foregroundStyle(.secondary)
        case .waiting:
            Image(systemName: "circle.dotted")
        case .lobby:
            Image(systemName: "person.2")
                .foregroundStyle(Color.pomAccent)
        case .active:
            Image(systemName: "timer")
                .foregroundStyle(Color.pomAccent)
        case .breakTime:
            Image(systemName: "cup.and.saucer.fill")
                .foregroundStyle(Color.blue)
        case .roundResult:
            Image(systemName: "checkmark.circle")
                .foregroundStyle(Color.pomSuccess)
        case .finished:
            Image(systemName: "checkmark.circle")
                .foregroundStyle(Color.pomSuccess)
        }
    }

    private var accessibilityLabel: String {
        switch phase {
        case .idle:        return "Pomodare: bezczynny"
        case .waiting:     return "Pomodare: oczekiwanie na partnera"
        case .lobby:       return "Pomodare: lobby"
        case .active:      return "Pomodare: runda w toku"
        case .breakTime:   return "Pomodare: przerwa"
        case .roundResult: return "Pomodare: koniec rundy"
        case .finished:    return "Pomodare: sesja zakończona"
        }
    }
}
