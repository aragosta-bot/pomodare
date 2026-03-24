import SwiftUI

@main
struct PomodareApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var model = SessionModel()

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environment(model)
        } label: {
            MenuBarIconView(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}

/// A simple icon that changes color based on session state.
struct MenuBarIconView: View {
    let model: SessionModel

    var body: some View {
        Image(systemName: "circle.fill")
            .foregroundStyle(model.menuBarColor)
            .font(.system(size: 14, weight: .medium))
    }
}
