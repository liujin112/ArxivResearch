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
            subtitle: "Make scheduled fetching visible, testable, and easy to repair."
        ) {
            SettingsCard(
                title: "Automation Health",
                subtitle: helperInstalled
                    ? "The hourly helper checks which subscriptions are due."
                    : "Install the helper before relying on scheduled fetching.",
                systemImage: "clock.arrow.circlepath"
            ) {
                HStack {
                    SettingsStatusPill(
                        text: automationNeedsAttention ? "Needs attention" : "Ready",
                        systemImage: automationNeedsAttention ? "exclamationmark.triangle.fill" : "checkmark.circle.fill",
                        color: automationNeedsAttention ? .red : .green
                    )
                    Spacer()
                    Text(helperStatusText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Divider()
                SettingsValueRow(label: "launchd status", value: helperStatusText)
                Divider()
                SettingsValueRow(label: "Last successful fetch", value: formatted(lastSuccessfulFetch, fallback: "Never"))
                Divider()
                SettingsValueRow(label: "Next scheduled run", value: nextScheduledRunText)
                Divider()
                SettingsValueRow(label: "Schedule", value: "Checks hourly; each subscription keeps its own interval")
                Divider()
                SettingsValueRow(label: "Time zone", value: TimeZone.current.localizedName(for: .standard, locale: .current) ?? TimeZone.current.identifier)
                Divider()
                SettingsValueRow(
                    label: "Subscriptions",
                    value: "\(enabledProfiles.count) enabled · \(disabledProfileCount) paused"
                )
            }

            SettingsCard(
                title: "Controls",
                subtitle: "Run a safe check now or repair the background helper.",
                systemImage: "switch.2"
            ) {
                Stepper("Helper interval: 60 minutes", value: .constant(60), in: 60...60)
                    .disabled(true)

                HStack(spacing: 10) {
                    Button {
                        Task { await testAutomation() }
                    } label: {
                        Label("Test Fetch", systemImage: "checkmark.seal")
                    }
                    .disabled(state.isWorking || enabledProfiles.isEmpty)

                    Button {
                        Task { await runAutomationNow() }
                    } label: {
                        Label("Run Now", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(state.isWorking || enabledProfiles.isEmpty)

                    Spacer()

                    Button {
                        state.installLaunchAgent()
                    } label: {
                        Label(
                            helperInstalled ? "Repair / Reinstall" : "Install Helper",
                            systemImage: helperInstalled ? "wrench.and.screwdriver" : "timer"
                        )
                    }
                    .disabled(state.isWorking)

                    Button {
                        openAutomationLogs()
                    } label: {
                        Label("Open Logs", systemImage: "doc.text.magnifyingglass")
                    }
                    .disabled(!logsDirectoryExists)
                    .help(logsDirectoryExists ? "Open helper logs in Finder" : "Logs will appear after the helper runs")
                }
            }

            SettingsCard(
                title: "Subscription Schedules",
                subtitle: "The helper only fetches enabled subscriptions whose interval has elapsed.",
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
        enabledProfiles.map { profile in
            guard let lastFetchedAt = profile.lastFetchedAt else { return Date() }
            return lastFetchedAt.addingTimeInterval(Double(profile.refreshIntervalHours * 3_600))
        }.min()
    }

    private var nextScheduledRunText: String {
        guard helperReady, let nextScheduledRun else { return "Not scheduled" }
        if nextScheduledRun <= Date() { return "Due now" }
        return formatted(nextScheduledRun, fallback: "Not scheduled")
    }

    private var helperPlistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(helperLabel).plist")
    }

    private var logsDirectoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/ArxivResearch", isDirectory: true)
    }

    private var helperInstalled: Bool {
        state.launchAgentStatus?.isInstalled
            ?? FileManager.default.fileExists(atPath: helperPlistURL.path)
    }

    private var helperReady: Bool {
        state.launchAgentStatus?.isLoaded == true
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

    private var automationNeedsAttention: Bool {
        !helperReady || enabledProfiles.isEmpty || state.launchAgentStatusError != nil
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

    private func runAutomationNow() async {
        guard !enabledProfiles.isEmpty else {
            state.statusMessage = "Enable a subscription before running automation"
            return
        }
        state.startDailyFetch()
    }

    private func openAutomationLogs() {
        guard logsDirectoryExists else {
            state.statusMessage = "Automation logs will appear after the helper runs"
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
        guard let lastFetchedAt = profile.lastFetchedAt else { return "Ready now" }
        let date = lastFetchedAt.addingTimeInterval(Double(profile.refreshIntervalHours * 3_600))
        return "Next " + date.formatted(date: .abbreviated, time: .shortened)
    }

    private var lastRunText: String {
        guard let lastFetchedAt = profile.lastFetchedAt else { return "Never fetched" }
        return "Last " + lastFetchedAt.formatted(date: .abbreviated, time: .shortened)
    }
}
