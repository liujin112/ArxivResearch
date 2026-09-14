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
    @StateObject private var updates = AppUpdateController()

    var body: some Scene {
        WindowGroup {
            ResearchWorkspaceView()
                .environmentObject(state)
                .environmentObject(updates)
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

                Button(state.selectedPaper.map { state.deepReadReport(for: $0.id) == nil ? "Deep Read" : "View Deep Read" } ?? "Deep Read") {
                    guard let paper = state.selectedPaper else { return }
                    state.showOrQueueDeepRead(paperID: paper.id)
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

            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    updates.checkForUpdates()
                }
                .disabled(!updates.isConfigured)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(state)
                .environmentObject(updates)
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
