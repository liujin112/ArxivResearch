import SwiftUI
import ArxivResearchCore

extension Notification.Name {
    /// Posted by the main menu when the paper search field should become first responder.
    static let arxivFocusPaperSearch = Notification.Name("ArxivResearch.focusPaperSearch")

    /// Posted by the main menu when the Activity UI should be revealed.
    static let arxivShowActivity = Notification.Name("ArxivResearch.showActivity")
}

@main
struct ArxivResearchApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup {
            ResearchWorkspaceView()
                .environmentObject(state)
        }
        .defaultSize(width: 1_480, height: 980)
        .windowToolbarStyle(.expanded)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Subscription") {
                    state.beginNewQuery()
                }
                .keyboardShortcut("n", modifiers: [.command])
            }

            CommandMenu("Navigate") {
                Button("Search Papers") {
                    NotificationCenter.default.post(name: .arxivFocusPaperSearch, object: nil)
                }
                .keyboardShortcut("f", modifiers: [.command])

                Button("Activity") {
                    NotificationCenter.default.post(name: .arxivShowActivity, object: nil)
                }
                .keyboardShortcut("0", modifiers: [.command])
            }

            CommandMenu("Subscription") {
                Button("Fetch All Subscriptions") {
                    state.startDailyFetch()
                }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(state.enabledSubscriptionCount == 0 || state.isWorking || state.isFetching)
            }

            CommandMenu("Paper") {
                Button("Save / Mark Interested") {
                    state.markInterested()
                }
                .keyboardShortcut("s", modifiers: [.command])
                .disabled(state.selectedPaper == nil || state.isWorking)

                Button("Deep Read") {
                    state.queueDeepRead()
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])
                .disabled(state.selectedPaper == nil || state.isWorking)
            }

            CommandMenu("Automation") {
                Button("Run Jobs") {
                    Task { await state.runPendingJobs() }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(state.pendingJobCount == 0 || state.isWorking)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(state)
                .frame(
                    minWidth: 780,
                    idealWidth: 860,
                    maxWidth: .infinity,
                    minHeight: 620,
                    idealHeight: 700,
                    maxHeight: .infinity
                )
        }
        .defaultSize(width: 860, height: 700)
    }
}
