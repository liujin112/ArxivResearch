import AppKit
import SwiftUI
import ArxivResearchCore

struct SettingsView: View {
    @EnvironmentObject private var state: AppState
    @State private var selection: SettingsDestination? = .general

    var body: some View {
        NavigationSplitView {
            List(SettingsDestination.allCases, selection: $selection) { destination in
                Label(destination.title, systemImage: destination.systemImage)
                    .tag(destination)
                    .padding(.vertical, 3)
            }
            .listStyle(.sidebar)
            .navigationTitle("Settings")
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 230)
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("ArxivResearch")
                        .font(.caption.weight(.semibold))
                    Text("Local-first research workspace")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            }
        } detail: {
            destinationView(selection ?? .general)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSplitViewStyle(.balanced)
    }

    @ViewBuilder
    private func destinationView(_ destination: SettingsDestination) -> some View {
        switch destination {
        case .general:
            GeneralSettingsView(selection: $selection)
        case .aiAnalysis:
            AIAnalysisSettingsView()
        case .integrations:
            IntegrationSettingsView()
        case .automation:
            AutomationSettingsView()
        case .advanced:
            AdvancedSettingsView()
        }
    }
}

private enum SettingsDestination: String, CaseIterable, Identifiable {
    case general
    case aiAnalysis
    case integrations
    case automation
    case advanced

    var id: Self { self }

    var title: String {
        switch self {
        case .general:
            "General"
        case .aiAnalysis:
            "AI & Analysis"
        case .integrations:
            "Integrations"
        case .automation:
            "Automation"
        case .advanced:
            "Advanced"
        }
    }

    var systemImage: String {
        switch self {
        case .general:
            "gearshape"
        case .aiAnalysis:
            "sparkles"
        case .integrations:
            "point.3.connected.trianglepath.dotted"
        case .automation:
            "clock.arrow.circlepath"
        case .advanced:
            "slider.horizontal.3"
        }
    }
}

private struct GeneralSettingsView: View {
    @EnvironmentObject private var state: AppState
    @Binding var selection: SettingsDestination?

    var body: some View {
        SettingsPage(
            title: "General",
            subtitle: "A quick view of your local research workspace."
        ) {
            SettingsCard(
                title: "Workspace",
                subtitle: "Papers, subscriptions, and jobs remain on this Mac.",
                systemImage: "macbook"
            ) {
                SettingsValueRow(label: "Subscriptions", value: "\(state.queryProfiles.count)")
                Divider()
                SettingsValueRow(label: "Papers", value: "\(state.papers.count)")
                Divider()
                SettingsValueRow(label: "Pending jobs", value: "\(state.pendingJobCount)")
            }

            SettingsCard(
                title: "Current Status",
                subtitle: "The latest message from fetching, analysis, or sync.",
                systemImage: "waveform.path.ecg"
            ) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    SettingsStatusPill(
                        text: state.isWorking ? "Working" : "Ready",
                        systemImage: state.isWorking ? "arrow.triangle.2.circlepath" : "checkmark.circle.fill",
                        color: state.isWorking ? .indigo : .green
                    )
                    Text(state.statusMessage)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Spacer(minLength: 0)
                }
            }

            SettingsCard(
                title: "Setup",
                subtitle: "Finish the two essentials before relying on the daily briefing.",
                systemImage: "checklist"
            ) {
                SettingsNavigationRow(
                    title: "Configure AI analysis",
                    detail: "Choose a provider, validate its key, and tune your research profile.",
                    systemImage: "brain"
                ) {
                    selection = .aiAnalysis
                }
                Divider()
                SettingsNavigationRow(
                    title: "Check daily automation",
                    detail: "Verify the helper, schedules, and the next planned run.",
                    systemImage: "clock.arrow.circlepath"
                ) {
                    selection = .automation
                }
            }
        }
    }
}

private struct AIAnalysisSettingsView: View {
    @EnvironmentObject private var state: AppState
    @State private var isShowingProviderKey = false

    var body: some View {
        SettingsPage(
            title: "AI & Analysis",
            subtitle: "Connect an LLM and shape how papers are summarized and ranked."
        ) {
            SettingsCard(
                title: "LLM Provider",
                subtitle: "Your key is stored in macOS Keychain.",
                systemImage: "brain"
            ) {
                Form {
                    Picker("Provider", selection: $state.providerKind) {
                        ForEach(ProviderKind.allCases, id: \.self) { kind in
                            Text(kind.rawValue).tag(kind)
                        }
                    }
                    TextField(
                        state.providerKind == .azureOpenAI ? "Endpoint" : "Base URL",
                        text: $state.providerBaseURL
                    )
                    if state.providerKind == .azureOpenAI {
                        TextField("Deployment Name", text: $state.providerDeploymentName)
                        TextField("API Version", text: $state.providerAPIVersion)
                        TextField("Custom Model", text: $state.providerModel)
                    } else {
                        TextField("Model", text: $state.providerModel)
                    }
                    LabeledContent("API Key") {
                        HStack(spacing: 8) {
                            Group {
                                if isShowingProviderKey {
                                    TextField("API Key", text: $state.providerAPIKeyDraft)
                                } else {
                                    SecureField("API Key", text: $state.providerAPIKeyDraft)
                                }
                            }
                            .textFieldStyle(.roundedBorder)

                            Button {
                                isShowingProviderKey.toggle()
                            } label: {
                                Image(systemName: isShowingProviderKey ? "eye.slash" : "eye")
                            }
                            .buttonStyle(.borderless)
                            .help(isShowingProviderKey ? "Hide API key" : "Show API key")
                            .accessibilityLabel(isShowingProviderKey ? "Hide API key" : "Show API key")
                        }
                    }
                }
                .formStyle(.grouped)

                HStack {
                    if state.providerValidationFingerprint.isEmpty {
                        SettingsStatusPill(
                            text: "Validation required",
                            systemImage: "exclamationmark.circle",
                            color: .orange
                        )
                    } else {
                        SettingsStatusPill(
                            text: "Validated",
                            systemImage: "checkmark.circle.fill",
                            color: .green
                        )
                    }
                    Spacer()
                    Button {
                        state.saveProviderKey()
                    } label: {
                        Label("Validate & Save LLM", systemImage: "checkmark.seal")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(state.isWorking)
                }

                if state.providerKind == .azureOpenAI {
                    Text("Azure uses Endpoint and Deployment Name. If the endpoint already contains /openai/deployments/<deployment>, that deployment is detected automatically.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            SettingsCard(
                title: "Research Profile",
                subtitle: "Give the model context about what matters to your work.",
                systemImage: "person.text.rectangle"
            ) {
                Text("Profile source")
                    .font(.subheadline.weight(.medium))
                TextEditor(text: $state.academicProfileInput)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 130)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(.separator, lineWidth: 1)
                    }

                HStack {
                    Button {
                        state.generateAcademicProfile()
                    } label: {
                        Label("Generate Academic Profile", systemImage: "sparkles")
                    }
                    .disabled(state.isWorking)
                    .help("Use the configured LLM to compress the source material into a reusable research profile")
                    Spacer()
                }

                Text("Generated profile")
                    .font(.subheadline.weight(.medium))
                    .padding(.top, 4)
                TextEditor(text: $state.generatedAcademicProfile)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 110)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(.separator, lineWidth: 1)
                    }
                Text("Future abstract analysis uses this concise profile, not the full source text above.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            SettingsCard(
                title: "Abstract Analysis",
                subtitle: "Control the language and editable instructions used for new summaries.",
                systemImage: "chart.line.text.clipboard"
            ) {
                Form {
                    Picker("Summary Language", selection: $state.summaryLanguage) {
                        ForEach(SummaryLanguage.allCases, id: \.self) { language in
                            Text(language.displayName).tag(language)
                        }
                    }
                    TextEditor(text: $state.summaryPromptInstructions)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 120)
                }
                .formStyle(.grouped)

                HStack {
                    Spacer()
                    Button {
                        state.saveSettings()
                        state.statusMessage = "Analysis settings saved"
                    } label: {
                        Label("Save Analysis Settings", systemImage: "text.badge.checkmark")
                    }
                }
            }

            SettingsCard(
                title: "Automatic Analysis",
                subtitle: "Analyze newly fetched papers once the LLM is ready.",
                systemImage: "wand.and.stars"
            ) {
                Toggle("Actively analyze papers without summaries", isOn: $state.activeAnalyzeUnanalyzedPapers)
                    .help("When enabled, the app scans papers without abstract analysis and starts summary jobs after the LLM settings are validated.")
                    .onChange(of: state.activeAnalyzeUnanalyzedPapers) {
                        state.saveSettings()
                        if state.activeAnalyzeUnanalyzedPapers {
                            state.analyzeUnanalyzedPapers()
                        }
                    }

                HStack {
                    Spacer()
                    Button {
                        state.saveSettings()
                        state.analyzeUnanalyzedPapers()
                    } label: {
                        Label("Analyze Missing Abstracts Now", systemImage: "sparkles")
                    }
                    .disabled(state.isWorking)
                    .help("Queue and start abstract analysis for every paper that does not have an LLM analysis yet.")
                }
            }
        }
    }
}

private struct IntegrationSettingsView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        SettingsPage(
            title: "Integrations",
            subtitle: "Send selected research notes to the tools you already use."
        ) {
            SettingsCard(
                title: "Notion",
                subtitle: "Create or update an inline Arxiv Papers data source.",
                systemImage: "square.grid.2x2"
            ) {
                Form {
                    TextField("Parent Page ID", text: $state.notionParentPageID)
                    TextField("Database ID", text: $state.notionDatabaseID)
                    TextField("Data Source ID", text: $state.notionDataSourceID)
                    Toggle("Auto-sync when summary or deep read updates", isOn: $state.notionAutoSync)
                    SecureField("Integration Token", text: $state.notionTokenDraft)
                }
                .formStyle(.grouped)

                HStack {
                    SettingsStatusPill(
                        text: state.notionDataSourceID.isEmpty ? "Needs setup" : "Configured",
                        systemImage: state.notionDataSourceID.isEmpty ? "exclamationmark.circle" : "checkmark.circle.fill",
                        color: state.notionDataSourceID.isEmpty ? .orange : .green
                    )
                    Spacer()
                    Button {
                        state.saveNotionToken()
                    } label: {
                        Label("Save Notion", systemImage: "key")
                    }
                    Button {
                        Task { await state.createNotionDatabase() }
                    } label: {
                        Label("Create Inline Database", systemImage: "square.grid.2x2")
                    }
                    .disabled(state.isWorking)
                }
            }

            SettingsCard(
                title: "Zotero",
                subtitle: "Sync paper metadata, tags, notes, and PDF attachments.",
                systemImage: "books.vertical"
            ) {
                Form {
                    Picker("Library", selection: $state.zoteroLibraryKind) {
                        Text("User").tag("user")
                        Text("Group").tag("group")
                    }
                    TextField("User or Group Library ID", text: $state.zoteroLibraryID)
                    TextField("Collection Key", text: $state.zoteroCollectionKey)
                    SecureField("Zotero API Key", text: $state.zoteroTokenDraft)
                }
                .formStyle(.grouped)

                HStack {
                    SettingsStatusPill(
                        text: zoteroIsConfigured ? "Configured" : "Needs setup",
                        systemImage: zoteroIsConfigured ? "checkmark.circle.fill" : "exclamationmark.circle",
                        color: zoteroIsConfigured ? .green : .orange
                    )
                    Spacer()
                    Button {
                        state.saveZoteroToken()
                    } label: {
                        Label("Save Zotero", systemImage: "key")
                    }
                }
            }
        }
    }

    private var zoteroIsConfigured: Bool {
        !state.zoteroLibraryID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !state.zoteroCollectionKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

private struct AutomationSettingsView: View {
    @EnvironmentObject private var state: AppState

    private let helperLabel = "com.arxivresearch.helper"

    var body: some View {
        SettingsPage(
            title: "Automation",
            subtitle: "Keep subscriptions current while the app is open, with optional background fetching after you quit."
        ) {
            SettingsCard(
                title: "Automatic Fetching",
                subtitle: "The app checks on launch, wake, activation, and once per hour while it remains open.",
                systemImage: "clock.arrow.circlepath"
            ) {
                HStack {
                    SettingsStatusPill(
                        text: automationNeedsAttention ? "Needs attention" : "App-open checks active",
                        systemImage: automationNeedsAttention ? "exclamationmark.triangle.fill" : "checkmark.circle.fill",
                        color: automationNeedsAttention ? .red : .green
                    )
                    Spacer()
                    Text(backgroundStatusText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Divider()
                SettingsValueRow(label: "Last successful fetch", value: formatted(lastSuccessfulFetch, fallback: "Never"))
                Divider()
                SettingsValueRow(label: "Next due subscription", value: nextScheduledRunText)
                Divider()
                SettingsValueRow(label: "App-open checks", value: "Launch, wake, activation, and every 60 minutes")
                Divider()
                SettingsValueRow(
                    label: "Subscriptions",
                    value: "\(enabledProfiles.count) enabled · \(disabledProfileCount) paused"
                )

                Divider()
                Toggle(
                    "Background automatic fetching",
                    isOn: Binding(
                        get: { state.backgroundAutomaticFetchingEnabled },
                        set: { state.setBackgroundAutomaticFetchingEnabled($0) }
                    )
                )
                .disabled(state.isUpdatingBackgroundAutomaticFetching)

                Text(state.backgroundAutomaticFetchingEnabled
                    ? "ArxivResearch will continue hourly due checks after the app is closed."
                    : "Optional. Leave this off if checking whenever the app opens is enough.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if state.backgroundAutomaticFetchingEnabled,
                   let error = state.launchAgentStatusError,
                   !error.isEmpty {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }

            SettingsCard(
                title: "Controls",
                subtitle: "Check only overdue subscriptions, fetch everything now, or test the arXiv connection.",
                systemImage: "switch.2"
            ) {
                HStack(spacing: 10) {
                    Button {
                        Task { await testAutomation() }
                    } label: {
                        Label("Test Connection", systemImage: "checkmark.seal")
                    }
                    .disabled(state.isWorking || enabledProfiles.isEmpty)

                    Button {
                        state.checkForDueSubscriptionsNow()
                    } label: {
                        Label("Check Due Now", systemImage: "clock.badge.checkmark")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(state.isWorking || enabledProfiles.isEmpty)

                    Button {
                        runAutomationNow()
                    } label: {
                        Label("Fetch All Now", systemImage: "arrow.down.circle")
                    }
                    .disabled(state.isWorking || enabledProfiles.isEmpty)
                }
            }

            SettingsCard(
                title: "Subscription Schedules",
                subtitle: "Each enabled subscription keeps its own interval; automatic checks fetch only those already due.",
                systemImage: "calendar.badge.clock"
            ) {
                if state.queryProfiles.isEmpty {
                    ContentUnavailableView(
                        "No Subscriptions",
                        systemImage: "calendar.badge.plus",
                        description: Text("Create a subscription in the main window to schedule daily fetching.")
                    )
                    .frame(minHeight: 150)
                } else {
                    ForEach(state.queryProfiles) { profile in
                        SubscriptionScheduleRow(profile: profile)
                        if profile.id != state.queryProfiles.last?.id {
                            Divider()
                        }
                    }
                }
            }

            SettingsCard(
                title: "Advanced Diagnostics",
                subtitle: "Background service state and logs are available here when troubleshooting is needed.",
                systemImage: "stethoscope"
            ) {
                DisclosureGroup("Background service details") {
                    VStack(alignment: .leading, spacing: 12) {
                        SettingsValueRow(label: "Background status", value: helperStatusText)
                        SettingsValueRow(label: "Service identifier", value: helperLabel)
                        if let error = state.launchAgentStatusError, !error.isEmpty {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .textSelection(.enabled)
                        }
                        HStack {
                            if state.backgroundAutomaticFetchingEnabled {
                                Button("Repair Background Service") {
                                    state.repairBackgroundAutomaticFetching()
                                }
                                .disabled(state.isWorking)
                            }
                            Button("Open Background Logs") {
                                openAutomationLogs()
                            }
                            .disabled(!logsDirectoryExists)
                        }
                    }
                    .padding(.top, 8)
                }
            }

            SettingsCard(
                title: "Latest Message",
                subtitle: "Errors remain visible here while you troubleshoot automation.",
                systemImage: "text.bubble"
            ) {
                Text(state.statusMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onAppear {
            state.refreshAutomationStatus()
        }
    }

    private var enabledProfiles: [QueryProfile] {
        state.queryProfiles.filter(\.isEnabled)
    }

    private var disabledProfileCount: Int {
        state.queryProfiles.count - enabledProfiles.count
    }

    private var lastSuccessfulFetch: Date? {
        state.queryProfiles.compactMap(\.lastFetchedAt).max()
    }

    private var nextScheduledRun: Date? {
        let now = Date()
        return enabledProfiles.map { $0.nextFetchAt ?? now }.min()
    }

    private var nextScheduledRunText: String {
        guard let nextScheduledRun else { return "Not scheduled" }
        if nextScheduledRun <= Date() { return "Due now" }
        return formatted(nextScheduledRun, fallback: "Not scheduled")
    }

    private var logsDirectoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/ArxivResearch", isDirectory: true)
    }

    private var helperStatusText: String {
        if let error = state.launchAgentStatusError, !error.isEmpty {
            return "Status unavailable"
        }
        switch state.launchAgentStatus?.state {
        case .running:
            return "Running now"
        case .loaded:
            return "Loaded · on schedule"
        case .installedNotLoaded:
            return "Installed · needs repair"
        case .notInstalled, nil:
            return "Not installed"
        }
    }

    private var logsDirectoryExists: Bool {
        FileManager.default.fileExists(atPath: logsDirectoryURL.path)
    }

    private var backgroundStatusText: String {
        if state.isUpdatingBackgroundAutomaticFetching {
            return "Updating background setting…"
        }
        if state.backgroundAutomaticFetchingEnabled {
            return state.launchAgentStatus?.isLoaded == true ? "Background on" : "Background needs attention"
        }
        return "Background off"
    }

    private var automationNeedsAttention: Bool {
        enabledProfiles.isEmpty
            || state.automationLastError != nil
            || (state.backgroundAutomaticFetchingEnabled
                && (state.launchAgentStatus?.isLoaded != true || state.launchAgentStatusError != nil))
    }

    private func formatted(_ date: Date?, fallback: String) -> String {
        date?.formatted(date: .abbreviated, time: .shortened) ?? fallback
    }

    private func testAutomation() async {
        guard let profile = enabledProfiles.first else {
            state.statusMessage = "Enable a subscription before testing automation"
            return
        }
        await state.testQuery(rawQuery: profile.requestRawQuery, maxResults: profile.maxResults)
    }

    private func runAutomationNow() {
        guard !enabledProfiles.isEmpty else {
            state.statusMessage = "Enable a subscription before running automation"
            return
        }
        state.startDailyFetch()
    }

    private func openAutomationLogs() {
        guard logsDirectoryExists else {
            state.statusMessage = "Background logs will appear after background fetching runs"
            return
        }
        NSWorkspace.shared.open(logsDirectoryURL)
    }
}

private struct AdvancedSettingsView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        SettingsPage(
            title: "Advanced",
            subtitle: "Tune generation behavior and inspect the prompts used by the app."
        ) {
            SettingsCard(
                title: "Generation",
                subtitle: "Defaults are conservative; increase concurrency carefully.",
                systemImage: "slider.horizontal.3"
            ) {
                Form {
                    Stepper(value: $state.providerMaxTokens, in: 256...32768, step: 256) {
                        Text("Max output tokens: \(state.providerMaxTokens)")
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Temperature: \(state.providerTemperature, specifier: "%.2f")")
                        Slider(value: $state.providerTemperature, in: 0...2, step: 0.05)
                    }
                    TextField("Top-p (optional, 0-1)", text: $state.providerTopPText)
                    Stepper(value: $state.providerConcurrency, in: 1...8) {
                        Text("LLM concurrency: \(state.providerConcurrency)")
                    }
                    Stepper(value: $state.providerRetryLimit, in: 0...5) {
                        Text("Retry attempts: \(state.providerRetryLimit)")
                    }
                }
                .formStyle(.grouped)
            }

            SettingsCard(
                title: "Locked Abstract Analysis Protocol",
                subtitle: "Shown for transparency and intentionally not editable.",
                systemImage: "lock.doc"
            ) {
                ScrollView {
                    Text(DefaultPrompts.summaryLockedProtocol)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 150, maxHeight: 220)
            }

            SettingsCard(
                title: "Deep Read Prompt",
                subtitle: "Instructions used when a full-paper analysis is queued.",
                systemImage: "doc.text.magnifyingglass"
            ) {
                TextEditor(text: $state.deepReadPrompt)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 240)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(.separator, lineWidth: 1)
                    }
                HStack {
                    Spacer()
                    Button {
                        state.saveSettings()
                        state.statusMessage = "Deep-read prompt saved"
                    } label: {
                        Label("Save Prompt", systemImage: "text.badge.checkmark")
                    }
                }
            }
        }
    }
}

private struct SettingsPage<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.largeTitle.weight(.semibold))
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 4)

                content
            }
            .frame(maxWidth: 760, alignment: .topLeading)
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(.indigo)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                content
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.8), lineWidth: 1)
        }
    }
}

private struct SettingsStatusPill: View {
    let text: String
    let systemImage: String
    let color: Color

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(color.opacity(0.12), in: Capsule())
            .accessibilityElement(children: .combine)
    }
}

private struct SettingsValueRow: View {
    let label: String
    let value: String

    var body: some View {
        LabeledContent(label) {
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .font(.callout)
    }
}

private struct SettingsNavigationRow: View {
    let title: String
    let detail: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(.indigo)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.callout.weight(.medium))
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
}

private struct SubscriptionScheduleRow: View {
    let profile: QueryProfile

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: profile.isEnabled ? "checkmark.circle.fill" : "pause.circle")
                .foregroundStyle(profile.isEnabled ? .green : .secondary)
                .accessibilityLabel(profile.isEnabled ? "Enabled" : "Paused")
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.name)
                    .font(.callout.weight(.medium))
                Text(profile.isEnabled ? "Every \(profile.refreshIntervalHours) hours" : "Paused")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(nextRunText)
                    .font(.caption.weight(.medium))
                Text(lastRunText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var nextRunText: String {
        guard profile.isEnabled else { return "Not scheduled" }
        guard let date = profile.nextFetchAt else { return "Ready now" }
        if profile.isDue(at: Date()) { return "Due now" }
        return "Next " + date.formatted(date: .abbreviated, time: .shortened)
    }

    private var lastRunText: String {
        guard let lastFetchedAt = profile.lastFetchedAt else { return "Never fetched" }
        return "Last " + lastFetchedAt.formatted(date: .abbreviated, time: .shortened)
    }
}
