import SwiftUI
import ArxivResearchCore

@main
struct ArxivResearchApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup {
            ResearchWorkspaceView()
                .environmentObject(state)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Query") {
                    state.beginNewQuery()
                }
                .keyboardShortcut("n", modifiers: [.command])
            }
        }

        Settings {
            SettingsView()
                .environmentObject(state)
                .frame(width: 560, height: 480)
        }
    }
}
