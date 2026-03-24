import SwiftUI

struct ContentView: View {
    @Environment(SessionModel.self) var model

    var body: some View {
        ZStack {
            Color(hex: "#1a1a1a")
                .ignoresSafeArea()

            Group {
                switch model.screen {
                case .home:
                    HomeView()
                case .waiting:
                    WaitingView()
                case .countdown(let count):
                    CountdownView(count: count)
                case .session:
                    SessionView()
                case .result:
                    ResultView()
                }
            }
            .environment(model)
        }
        .frame(width: 280)
        .frame(minHeight: 320)
    }
}
