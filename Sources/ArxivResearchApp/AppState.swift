import Foundation
import SwiftUI
import AppKit
import ArxivResearchCore

enum LibrarySidebarSelection: Hashable {
    case all
    case thisWeek(PaperDateField)
    case date(PaperDateField, Date)
    case query(UUID)
}

struct LibraryDateBucket: Identifiable, Hashable {
    var id: LibrarySidebarSelection { selection }
    var selection: LibrarySidebarSelection
    var title: String
    var count: Int
}

struct ActiveOperationState: Equatable {
    enum Kind: Equatable {
        case fetching
        case runningJobs
        case other
    }

    var kind: Kind
    var title: String
    var detail: String
    var completedUnitCount: Int
    var totalUnitCount: Int
    var startedAt: Date

    var progress: Double? {
        guard totalUnitCount > 0 else { return nil }
        return min(max(Double(completedUnitCount) / Double(totalUnitCount), 0), 1)
    }
}

private struct AutomationStatusSnapshot: Sendable {
    var status: LaunchAgentStatus?
    var errorDescription: String?
}

private struct AutomationInstallSnapshot: Sendable {
    var status: LaunchAgentStatus?
    var errorDescription: String?
}

private enum AutomaticFetchTrigger: String, Sendable {
    case appLaunch
    case becameActive
    case systemWake
    case hourlyCheck
    case manualCheck

    var statusDescription: String {
        switch self {
        case .appLaunch: "app launch"
        case .becameActive: "app activation"
        case .systemWake: "wake"
        case .hourlyCheck: "hourly check"
        case .manualCheck: "manual check"
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published var queryProfiles: [QueryProfile] = []
    @Published var papers: [Paper] = []
    @Published private(set) var briefingPapers: [Paper] = []
    @Published private(set) var recentPapers: [Paper] = []
    @Published private(set) var savedPaperCount = 0
    @Published var sidebarSelection: LibrarySidebarSelection = .all
    @Published var libraryDateField: PaperDateField = .updated
    @Published var selectedQueryID: QueryProfile.ID?
    @Published var selectedPaperID: Paper.ID?
    @Published var selectedPaperIDs: Set<Paper.ID> = []
    @Published var latestAnalysesByPaperID: [String: LLMAnalysis] = [:]
    @Published private(set) var latestDeepReadsByPaperID: [String: DeepReadReport] = [:]
    @Published var statusMessage = "Ready"
    @Published var pendingJobCount = 0
    @Published var recentJobs: [SyncJob] = []
    @Published var isWorking = false
    @Published var queryPreviewURL = ""
    @Published var activeOperation: ActiveOperationState?
    @Published var automationLastError: String?
    @Published var launchAgentStatus: LaunchAgentStatus?
    @Published var launchAgentStatusError: String?
    @Published private(set) var backgroundAutomaticFetchingEnabled = false
    @Published private(set) var isUpdatingBackgroundAutomaticFetching = false
    @Published var isActivityRailVisible = true

    @Published var providerKind: ProviderKind = .openAI
    @Published var providerModel = "gpt-4.1"
    @Published var providerDeploymentName = ""
    @Published var providerBaseURL = "https://api.openai.com"
    @Published var providerAPIVersion = "2024-10-21"
    @Published var providerMaxTokens = 4096
    @Published var providerTemperature = 0.2
    @Published var providerTopPText = ""
    @Published var providerConcurrency = 2
    @Published var providerRetryLimit = 1
    @Published var providerValidationFingerprint = ""
    @Published var providerAPIKeyDraft = ""
    @Published var notionParentPageID = ""
    @Published var notionDatabaseID = ""
    @Published var notionDataSourceID = ""
    @Published var notionAutoSync = false
    @Published var activeAnalyzeUnanalyzedPapers = true
    @Published var notionTokenDraft = ""
    @Published var zoteroLibraryKind = "user"
    @Published var zoteroLibraryID = ""
    @Published var zoteroCollectionKey = ""
    @Published var zoteroTokenDraft = ""
    @Published var academicProfileInput = ""
    @Published var generatedAcademicProfile = ""
    @Published var summaryLanguage: SummaryLanguage = .english
    @Published var summaryPromptInstructions = DefaultPrompts.summaryInstructions
    @Published var deepReadPrompt = DefaultPrompts.deepRead
    @Published var isShowingQueryEditor = false
    @Published var editingQueryProfile: QueryProfile?

    private var store: SQLiteResearchStore?
    private let keychain = KeychainStore()
    private let defaults = UserDefaults.standard
    private let runtimeSettingsStore = try? RuntimeSettingsStore.default()
    private var isAutoRunScheduled = false
    private var busyOperationIDs = Set<UUID>()
    private var inFlightFetchQueryIDs = Set<QueryProfile.ID>()
    private var isRunningJobs = false
    private var needsQueuedJobDrain = false
    private var dailyFetchTask: Task<Void, Never>?
    private var databaseChangeObserver: NSObjectProtocol?
    private var automationStatusTask: Task<Void, Never>?
    private var helperInstallTask: Task<Void, Never>?
    private var automaticFetchTask: Task<Void, Never>?
    private var periodicDueCheckTask: Task<Void, Never>?
    private var workspaceWakeObserver: NSObjectProtocol?

    var selectedPaper: Paper? {
        papers.first { $0.id == selectedPaperID }
    }

    var selectedPaperAnalysis: LLMAnalysis? {
        guard let selectedPaperID else { return nil }
        return latestAnalysesByPaperID[selectedPaperID]
    }

    var deepReadMarkdown: String {
        guard let selectedPaperID else { return "" }
        return latestDeepReadsByPaperID[selectedPaperID]?.markdown ?? ""
    }

    var lastSuccessfulFetchAt: Date? {
        queryProfiles.compactMap(\.lastFetchedAt).max()
    }

    var nextScheduledFetchAt: Date? {
        let now = Date()
        return queryProfiles
            .filter(\.isEnabled)
            .map { $0.nextFetchAt ?? now }
            .min()
    }

    var enabledSubscriptionCount: Int {
        queryProfiles.filter(\.isEnabled).count
    }

    var failedJobs: [SyncJob] {
        recentJobs.filter { $0.state == .failed }
    }

    var isFetching: Bool {
        activeOperation?.kind == .fetching
    }

    private var automationHelperURL: URL {
        Bundle.main.bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Helpers", isDirectory: true)
            .appendingPathComponent("ArxivResearchHelper")
    }

    var selectedQueryFilterID: UUID? {
        if case let .query(id) = sidebarSelection {
            return id
        }
        return nil
    }

    var selectedLibraryDateFilter: PaperLibraryDateFilter {
        if case let .date(field, date) = sidebarSelection {
            return .day(field: field, date: date)
        }
        if case let .thisWeek(field) = sidebarSelection {
            return .thisWeek(field: field, referenceDate: Date())
        }
        return .all
    }

    var selectedSubscriptionID: UUID? {
        if case let .query(id) = sidebarSelection {
            return id
        }
        return nil
    }

    var libraryDateBuckets: [LibraryDateBucket] {
        PaperLibraryDateBuckets.make(for: papers, field: libraryDateField, calendar: .current).map { bucket in
            LibraryDateBucket(
                selection: sidebarSelection(for: bucket.filter),
                title: bucket.title,
                count: bucket.count
            )
        }
    }

    var libraryWeekBucket: LibraryDateBucket {
        let bucket = PaperLibraryDateBuckets.thisWeekBucket(
            for: papers,
            field: libraryDateField,
            calendar: .current
        )
        return LibraryDateBucket(
            selection: sidebarSelection(for: bucket.filter),
            title: bucket.title,
            count: bucket.count
        )
    }

    var jobStatusText: String {
        let pending = recentJobs.filter { $0.state == .pending }.count
        let running = recentJobs.filter { $0.state == .running }.count
        let failed = recentJobs.filter { $0.state == .failed }.count
        if pending == 0 && running == 0 && failed == 0 {
            return "No pending jobs"
        }
        return "\(pending) pending, \(running) running, \(failed) failed"
    }

    var llmJobCount: Int {
        recentJobs.filter { $0.kind == .summarizeAbstract || $0.kind == .deepRead }.count
    }

    var notionJobCount: Int {
        recentJobs.filter { $0.kind == .syncNotion }.count
    }

    var zoteroJobCount: Int {
        recentJobs.filter { $0.kind == .syncZotero }.count
    }

    init() {
        backgroundAutomaticFetchingEnabled = defaults.bool(forKey: DefaultsKey.backgroundAutomaticFetching)
        loadSettings()
        do {
            let dbURL = try AppEnvironment.defaultDatabaseURL()
            store = try SQLiteResearchStore(path: dbURL)
            try load()
        } catch {
            statusMessage = "Local store unavailable: \(error.localizedDescription)"
            seedPreviewData()
        }
        refreshAutomationStatus()
#if os(macOS)
        databaseChangeObserver = DistributedNotificationCenter.default().addObserver(
            forName: .arxivResearchDatabaseDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshExternalChanges(reportStatus: false)
            }
        }

        workspaceWakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshExternalChanges(reportStatus: false)
                self?.scheduleAutomaticFetch(trigger: .systemWake)
            }
        }
#endif
        startForegroundAutomaticFetching()
    }

    deinit {
        automaticFetchTask?.cancel()
        periodicDueCheckTask?.cancel()
    }

    func load() throws {
        guard let store else { return }
        let previousPaperID = selectedPaperID
        let previousPaperIDs = selectedPaperIDs
        let previousSidebarSelection = sidebarSelection
        queryProfiles = try store.fetchQueryProfiles()
        papers = try store.fetchPapers()
        if queryProfiles.isEmpty {
            let profile = QueryProfile(
                name: "LLM Agents",
                rawQuery: "cat:cs.AI+AND+%28all:agent+OR+all:%22language+model%22%29+ANDNOT+all:survey"
            )
            try store.upsertQueryProfile(profile)
            queryProfiles = [profile]
        }
        if papers.isEmpty {
            seedPreviewData()
        }
        try refreshLatestAnalyses()
        if selectedQueryID == nil || !queryProfiles.contains(where: { $0.id == selectedQueryID }) {
            selectedQueryID = queryProfiles.first?.id
        }
        sidebarSelection = validatedSidebarSelection(previousSidebarSelection)
        if let previousPaperID, papers.contains(where: { $0.id == previousPaperID }) {
            selectedPaperID = previousPaperID
        } else {
            selectedPaperID = papers.first?.id
        }
        selectedPaperIDs = previousPaperIDs.intersection(Set(papers.map(\.id)))
        if selectedPaperIDs.isEmpty, let selectedPaperID {
            selectedPaperIDs = [selectedPaperID]
        }
        try refreshJobCount()
        updateQueryPreview()
    }

    func reload() {
        do {
            try load()
            statusMessage = "Reloaded local data"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func refreshExternalChanges(reportStatus: Bool = true) {
        do {
            try load()
            refreshAutomationStatus()
            if reportStatus {
                statusMessage = "Up to date"
            }
        } catch {
            statusMessage = "Could not refresh background changes: \(error.localizedDescription)"
        }
    }

    func handleAppBecameActive() {
        refreshExternalChanges(reportStatus: false)
        scheduleAutomaticFetch(trigger: .becameActive)
    }

    func checkForDueSubscriptionsNow() {
        scheduleAutomaticFetch(trigger: .manualCheck)
    }

    private func startForegroundAutomaticFetching() {
        scheduleAutomaticFetch(trigger: .appLaunch)
        periodicDueCheckTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(3_600))
                } catch {
                    return
                }
                if let self {
                    self.scheduleAutomaticFetch(trigger: .hourlyCheck)
                } else {
                    return
                }
            }
        }
    }

    private func scheduleAutomaticFetch(trigger: AutomaticFetchTrigger) {
        guard automaticFetchTask == nil else { return }
        automaticFetchTask = Task { [weak self] in
            guard let self else { return }
            await self.performAutomaticFetch(trigger: trigger)
            self.automaticFetchTask = nil
        }
    }

    private func performAutomaticFetch(trigger: AutomaticFetchTrigger) async {
        guard let store else { return }
        let now = Date()
        let settings = currentRuntimeSettings()
        let shouldQueueSummaries = settings.activeAnalyzeUnanalyzedPapers
            && settings.canQueueSummariesWithoutSecrets
        let service = ResearchAutomationService(
            store: store,
            arxivClient: ArxivHTTPClient(),
            queueSummaries: shouldQueueSummaries
        )

        do {
            let report = try await service.runOnce(now: now)
            try load()

            if !report.failures.isEmpty {
                let failedNames = report.failures.map(\.profileName).joined(separator: ", ")
                let message = "Automatic fetch after \(trigger.statusDescription) failed for: \(failedNames)"
                automationLastError = message
                statusMessage = message
            } else if !report.succeededProfileIDs.isEmpty {
                automationLastError = nil
                let count = report.succeededProfileIDs.count
                statusMessage = count == 1
                    ? "Automatically fetched 1 overdue subscription after \(trigger.statusDescription)."
                    : "Automatically fetched \(count) overdue subscriptions after \(trigger.statusDescription)."
            }

            if shouldQueueSummaries, report.succeededProfileIDs.isEmpty == false {
                startQueuedJobsIfIdle()
            }
        } catch is CancellationError {
            return
        } catch {
            let message = "Automatic fetch check failed: \(error.localizedDescription)"
            automationLastError = message
            statusMessage = message
        }
    }

    func addQuery() {
        beginNewQuery()
    }

    func beginNewQuery() {
        editingQueryProfile = nil
        isShowingQueryEditor = true
    }

    func beginEditQuery(id: QueryProfile.ID) {
        guard let profile = queryProfiles.first(where: { $0.id == id }) else { return }
        selectedQueryID = id
        editingQueryProfile = profile
        isShowingQueryEditor = true
    }

    func saveQuery(
        id: QueryProfile.ID,
        name: String,
        rawQuery: String,
        structuredQueryRoot: StructuredQueryGroup?,
        usesRawQuery: Bool,
        refreshIntervalHours: Int,
        isEnabled: Bool,
        maxResults: Int,
        submittedAfter: Date?
    ) {
        guard let index = queryProfiles.firstIndex(where: { $0.id == id }) else { return }
        var profile = queryProfiles[index]
        profile.name = name
        profile.rawQuery = rawQuery
        profile.structuredQueryRoot = structuredQueryRoot
        profile.usesRawQuery = usesRawQuery
        profile.refreshIntervalHours = refreshIntervalHours
        profile.isEnabled = isEnabled
        profile.maxResults = maxResults
        profile.submittedAfter = submittedAfter
        queryProfiles[index] = profile
        do {
            try store?.upsertQueryProfile(profile)
            statusMessage = "Query saved"
            updateQueryPreview()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func saveQueryDraft(
        id: QueryProfile.ID?,
        name: String,
        rawQuery: String,
        structuredQueryRoot: StructuredQueryGroup?,
        usesRawQuery: Bool,
        refreshIntervalHours: Int,
        isEnabled: Bool,
        maxResults: Int,
        submittedAfter: Date?
    ) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedQuery = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let requestQuery = QueryProfile.composeRequestRawQuery(rawQuery: trimmedQuery, submittedAfter: submittedAfter)
        guard !requestQuery.isEmpty else {
            statusMessage = "Query cannot be empty"
            return
        }
        do {
            if let id, let index = queryProfiles.firstIndex(where: { $0.id == id }) {
                var profile = queryProfiles[index]
                profile.name = trimmedName.isEmpty ? "Untitled Query" : trimmedName
                profile.rawQuery = trimmedQuery
                profile.structuredQueryRoot = structuredQueryRoot
                profile.usesRawQuery = usesRawQuery
                profile.refreshIntervalHours = refreshIntervalHours
                profile.isEnabled = isEnabled
                profile.maxResults = maxResults
                profile.submittedAfter = submittedAfter
                queryProfiles[index] = profile
                try store?.upsertQueryProfile(profile)
                selectedQueryID = id
                statusMessage = "Query saved"
            } else {
                let profile = QueryProfile(
                    name: trimmedName.isEmpty ? "Untitled Query" : trimmedName,
                    rawQuery: trimmedQuery,
                    structuredQueryRoot: structuredQueryRoot,
                    usesRawQuery: usesRawQuery,
                    refreshIntervalHours: refreshIntervalHours,
                    isEnabled: isEnabled,
                    maxResults: maxResults,
                    submittedAfter: submittedAfter
                )
                queryProfiles.append(profile)
                try store?.upsertQueryProfile(profile)
                selectedQueryID = profile.id
                statusMessage = "Query added"
            }
            isShowingQueryEditor = false
            editingQueryProfile = nil
            updateQueryPreview()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func toggleQueryEnabled(id: QueryProfile.ID) {
        guard let index = queryProfiles.firstIndex(where: { $0.id == id }) else { return }
        var profile = queryProfiles[index]
        profile.isEnabled.toggle()
        queryProfiles[index] = profile
        do {
            try store?.upsertQueryProfile(profile)
            statusMessage = profile.isEnabled ? "Query enabled" : "Query disabled"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func deleteSelectedQuery(deleteAssociatedPapers: Bool = false) {
        guard let selectedQueryID else { return }
        deleteQuery(id: selectedQueryID, deleteAssociatedPapers: deleteAssociatedPapers)
    }

    func deleteQuery(id: QueryProfile.ID, deleteAssociatedPapers: Bool = false) {
        do {
            try store?.deleteQueryProfile(id: id, deleteAssociatedPapers: deleteAssociatedPapers)
            queryProfiles.removeAll { $0.id == id }
            papers = try store?.fetchPapers() ?? papers
            try refreshLatestAnalyses()
            selectedPaperIDs = Set(selectedPaperIDs.filter { paperID in
                papers.contains { $0.id == paperID }
            })
            if let selectedPaperID, !papers.contains(where: { $0.id == selectedPaperID }) {
                self.selectedPaperID = papers.first?.id
                selectedPaperIDs = Set(self.selectedPaperID.map { [$0] } ?? [])
            }
            if case let .query(queryID) = sidebarSelection, queryID == id {
                sidebarSelection = .all
            }
            self.selectedQueryID = queryProfiles.first?.id
            statusMessage = deleteAssociatedPapers ? "Query and associated papers removed" : "Query removed"
            updateQueryPreview()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func selectedQuery() -> QueryProfile? {
        queryProfiles.first { $0.id == selectedQueryID }
    }

    func queryPaperCount(id: QueryProfile.ID) -> Int {
        papers.filter { $0.queryProfileIDs.contains(id) }.count
    }

    func selectPaper(_ paper: Paper, replaceSelection: Bool = true) {
        focusPaper(id: paper.id, replaceSelection: replaceSelection)
    }

    func focusPaper(id: Paper.ID, replaceSelection: Bool = false) {
        guard papers.contains(where: { $0.id == id }) else { return }
        guard selectedPaperID != id || (replaceSelection && selectedPaperIDs != [id]) else { return }
        selectedPaperID = id
        if replaceSelection {
            selectedPaperIDs = [id]
        }
    }

    func markInterested() {
        guard let paper = selectedPaper else { return }
        setInterested(paperID: paper.arxivID)
    }

    func setInterested(paperID: Paper.ID) {
        guard var paper = papers.first(where: { $0.id == paperID }) else { return }
        paper.status = .interested
        update(paper)
    }

    func archivePaper(paperID: Paper.ID) {
        guard var paper = papers.first(where: { $0.id == paperID }) else { return }
        paper.status = .archived
        update(paper)
    }

    func queueSummary(paperID: Paper.ID) {
        queueSummaries(paperIDs: [paperID])
    }

    func queueSummaries(paperIDs: [Paper.ID]) {
        Task { await queueSummariesNow(paperIDs: paperIDs) }
    }

    private func queueSummariesNow(paperIDs: [Paper.ID]) async {
        let targetIDs = Set(paperIDs)
        guard !targetIDs.isEmpty else { return }
        do {
            guard try await makeAutomationConfiguration().canProcess(.summarizeAbstract) else {
                statusMessage = missingConfigurationMessage(for: .summarizeAbstract)
                return
            }
            var queued = 0
            for paperID in targetIDs where papers.contains(where: { $0.id == paperID }) {
                let job = try store?.enqueueIfNeeded(try SyncJob.paperJob(kind: .summarizeAbstract, paperID: paperID))
                if job?.state == .pending {
                    queued += 1
                }
            }
            try refreshJobCount()
            if queued > 0 {
                statusMessage = queued == 1 ? "Abstract analysis queued; starting jobs" : "\(queued) abstract analyses queued; starting jobs"
                startQueuedJobsIfIdle()
            } else {
                statusMessage = "Selected papers are already queued or running"
            }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func analyzeUnanalyzedPapers() {
        Task { await analyzeUnanalyzedPapersNow() }
    }

    func analyzeUnanalyzedPapersNow(paperIDs: Set<Paper.ID>? = nil) async {
        guard let store else { return }
        await runBusy("Queuing abstract analysis") {
            let configuration = try await makeAutomationConfiguration()
            guard configuration.canProcess(.summarizeAbstract) else {
                statusMessage = missingConfigurationMessage(for: .summarizeAbstract)
                return
            }
            let service = ResearchAutomationService(
                store: store,
                arxivClient: ArxivHTTPClient(),
                queueSummaries: true
            )
            let queuedJobs = try service.queueUnanalyzedSummaries(paperIDs: paperIDs)
            try refreshJobCount()
            guard !queuedJobs.isEmpty else {
                statusMessage = "No unanalyzed papers need abstract analysis"
                return
            }
            let processor = AutomationJobProcessor(store: store, configuration: configuration) { [weak self] in
                try self?.refreshJobCount()
            }
            let limit = try store.countJobs(kind: .summarizeAbstract, state: .pending)
                + store.countJobs(kind: .summarizeAbstract, state: .running)
            var result = try await processor.runPendingJobs(limit: max(queuedJobs.count, limit), kind: .summarizeAbstract)
            if result.succeeded > 0 || result.failed > 0 {
                try await drainFollowUpJobs(using: processor, into: &result)
            }
            papers = try store.fetchPapers()
            try refreshLatestAnalyses()
            try refreshJobCount()
            statusMessage = "Abstract analysis: \(result.succeeded) succeeded, \(result.failed) failed, \(result.skipped) skipped"
        }
    }

    func queueDeepRead() {
        guard let paper = selectedPaper else { return }
        queueDeepRead(paperID: paper.arxivID)
    }

    func queueDeepRead(paperID: Paper.ID) {
        Task { await queueDeepReadNow(paperID: paperID) }
    }

    private func queueDeepReadNow(paperID: Paper.ID) async {
        guard var paper = papers.first(where: { $0.id == paperID }) else { return }
        do {
            guard try await makeAutomationConfiguration().canProcess(.deepRead) else {
                statusMessage = missingConfigurationMessage(for: .deepRead)
                return
            }
            paper.status = .deepReading
            try store?.upsertPaper(paper)
            if let index = papers.firstIndex(where: { $0.id == paperID }) {
                papers[index] = paper
            }
            try store?.enqueueIfNeeded(try SyncJob.paperJob(kind: .deepRead, paperID: paperID))
            try refreshJobCount()
            statusMessage = "Deep read queued for \(paperID); starting jobs"
            startQueuedJobsIfIdle()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func syncNotion() {
        guard let paper = selectedPaper else { return }
        syncNotion(paperID: paper.arxivID)
    }

    func syncNotion(paperID: Paper.ID) {
        Task { await syncNotionNow(paperID: paperID) }
    }

    private func syncNotionNow(paperID: Paper.ID) async {
        do {
            guard try await makeAutomationConfiguration().canProcess(.syncNotion) else {
                statusMessage = missingConfigurationMessage(for: .syncNotion)
                return
            }
            try store?.enqueueIfNeeded(try SyncJob.paperJob(kind: .syncNotion, paperID: paperID))
            try refreshJobCount()
            statusMessage = "Notion sync queued; starting jobs"
            startQueuedJobsIfIdle()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func syncZotero() {
        guard let paper = selectedPaper else { return }
        syncZotero(paperID: paper.arxivID)
    }

    func syncZotero(paperID: Paper.ID) {
        Task { await syncZoteroNow(paperID: paperID) }
    }

    private func syncZoteroNow(paperID: Paper.ID) async {
        do {
            guard try await makeAutomationConfiguration().canProcess(.syncZotero) else {
                statusMessage = missingConfigurationMessage(for: .syncZotero)
                return
            }
            try store?.enqueueIfNeeded(try SyncJob.paperJob(kind: .syncZotero, paperID: paperID))
            try refreshJobCount()
            statusMessage = "Zotero sync queued; starting jobs"
            startQueuedJobsIfIdle()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func deletePaper(paperID: Paper.ID) {
        do {
            try store?.deletePaper(arxivID: paperID)
            papers.removeAll { $0.id == paperID }
            latestAnalysesByPaperID.removeValue(forKey: paperID)
            latestDeepReadsByPaperID.removeValue(forKey: paperID)
            rebuildBriefingPapers()
            selectedPaperIDs.remove(paperID)
            if selectedPaperID == paperID {
                selectedPaperID = papers.first?.id
                selectedPaperIDs = Set(selectedPaperID.map { [$0] } ?? [])
            }
            try refreshJobCount()
            statusMessage = "Deleted \(paperID)"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func generateAcademicProfile() {
        Task { await generateAcademicProfileNow() }
    }

    func generateAcademicProfileNow() async {
        await runBusy("Generating academic profile") {
            let rawInput = academicProfileInput.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rawInput.isEmpty else {
                throw AppActionError.missingAcademicProfileInput
            }
            let configuration = try await makeAutomationConfiguration()
            guard let provider = configuration.llmProvider,
                  let apiKey = configuration.llmAPIKey,
                  !apiKey.isEmpty
            else {
                throw AppActionError.missingLLMForProfile
            }
            let payload = LLMPromptPayload
                .academicProfilePrompt(rawInput: rawInput, existingProfile: generatedAcademicProfile)
                .applying(maxTokens: providerMaxTokens, temperature: providerTemperature, topP: parsedProviderTopP)
            generatedAcademicProfile = try await completeLLM(
                provider: provider,
                apiKey: apiKey,
                payload: payload,
                retryLimit: providerRetryLimit
            )
            saveSettings()
            statusMessage = "Academic profile generated"
        }
    }

    func testSelectedQuery() async {
        guard let profile = selectedQuery() else { return }
        await testQuery(rawQuery: profile.requestRawQuery, maxResults: profile.maxResults)
    }

    func testQuery(rawQuery: String, maxResults: Int = 50) async {
        await runBusy("Testing query") {
            let request = ArxivAPIRequest(searchQuery: .raw(rawQuery), maxResults: maxResults)
            queryPreviewURL = try request.url().absoluteString
            let feed = try await ArxivHTTPClient().search(request)
            statusMessage = "Query OK: \(feed.entries.count) shown, \(feed.totalResults) total"
        }
    }

    func fetchSelectedQueryNow() async {
        guard let id = selectedSubscriptionID else {
            statusMessage = "Select a subscription before fetching."
            return
        }
        await fetchQuery(id: id)
    }

    @discardableResult
    func fetchQuery(id: QueryProfile.ID) async -> Bool {
        guard !inFlightFetchQueryIDs.contains(id) else {
            statusMessage = "That subscription is already fetching."
            return false
        }
        guard let profile = queryProfiles.first(where: { $0.id == id }), let store else { return false }
        inFlightFetchQueryIDs.insert(id)
        defer { inFlightFetchQueryIDs.remove(id) }
        let leaseOwnerID = "app-\(UUID().uuidString)"
        do {
            guard try store.claimQueryFetch(profileID: id, ownerID: leaseOwnerID) else {
                statusMessage = "This subscription is already being fetched in the background."
                return false
            }
        } catch {
            statusMessage = "Could not coordinate this fetch: \(error.localizedDescription)"
            return false
        }
        defer { try? store.releaseQueryFetch(profileID: id, ownerID: leaseOwnerID) }
        selectedQueryID = id
        var didSucceed = false
        await runBusy("Fetching arXiv") {
            try Task.checkCancellation()
            let settings = currentRuntimeSettings()
            let shouldQueueSummaries = settings.activeAnalyzeUnanalyzedPapers && settings.canQueueSummariesWithoutSecrets
            let request = ArxivAPIRequest(searchQuery: .raw(profile.requestRawQuery), maxResults: profile.maxResults)
            queryPreviewURL = try request.url().absoluteString
            let feed = try await ArxivHTTPClient().search(request)
            try Task.checkCancellation()
            let fetchedAt = Date()
            var queuedSummaryJobIDs: [SyncJob.ID] = []
            var seenSummaryJobIDs = Set<SyncJob.ID>()
            for entry in feed.entries {
                var paper = entry.asPaper(queryProfileID: profile.id)
                paper.addedAt = fetchedAt
                if let existing = try store.fetchPaper(arxivID: paper.arxivID) {
                    paper.queryProfileIDs = Array(Set(existing.queryProfileIDs + [profile.id]))
                    paper.status = existing.status
                    paper.tags = existing.tags
                    paper.zoteroKey = existing.zoteroKey
                    paper.notionPageID = existing.notionPageID
                    paper.addedAt = existing.addedAt ?? fetchedAt
                }
                try store.upsertPaper(paper)
                if shouldQueueSummaries, try store.latestAnalysis(for: paper.arxivID) == nil {
                    let summaryJob = try store.enqueueIfNeeded(try SyncJob.paperJob(kind: .summarizeAbstract, paperID: entry.arxivID))
                    if summaryJob.state == .pending, !seenSummaryJobIDs.contains(summaryJob.id) {
                        queuedSummaryJobIDs.append(summaryJob.id)
                        seenSummaryJobIDs.insert(summaryJob.id)
                    }
                }
            }

            var summaryRunResult = AutomationJobRunResult()
            var summaryRunMessage = ""
            if !queuedSummaryJobIDs.isEmpty {
                do {
                    let configuration = try await makeAutomationConfiguration()
                    if configuration.canProcess(.summarizeAbstract) {
                        let processor = AutomationJobProcessor(store: store, configuration: configuration) { [weak self] in
                            try self?.refreshJobCount()
                        }
                        for jobID in queuedSummaryJobIDs {
                            let result = try await processor.runJob(id: jobID, allowRetryFailed: false)
                            summaryRunResult.succeeded += result.succeeded
                            summaryRunResult.failed += result.failed
                            summaryRunResult.skipped += result.skipped
                        }
                        try await drainFollowUpJobs(using: processor, into: &summaryRunResult)
                        summaryRunMessage = "; summaries ran: \(summaryRunResult.succeeded) succeeded, \(summaryRunResult.failed) failed, \(summaryRunResult.skipped) skipped"
                    } else {
                        summaryRunMessage = "; summaries queued but LLM is not ready"
                    }
                } catch {
                    summaryRunMessage = "; summaries queued but auto-run failed: \(error.localizedDescription)"
                }
            }
            if var latestProfile = try store.fetchQueryProfile(id: profile.id) {
                latestProfile.lastFetchedAt = Date()
                try store.upsertQueryProfile(latestProfile)
            }
            queryProfiles = try store.fetchQueryProfiles()
            papers = try store.fetchPapers()
            try refreshLatestAnalyses()
            selectedPaperID = papers.first?.id
            try refreshJobCount()
            if shouldQueueSummaries {
                statusMessage = "Fetched \(feed.entries.count) papers, queued \(queuedSummaryJobIDs.count) summaries\(summaryRunMessage)"
            } else {
                statusMessage = "Fetched \(feed.entries.count) papers; validate LLM before queuing summaries"
            }
            didSucceed = true
        }
        return didSucceed
    }

    func startDailyFetch() {
        guard dailyFetchTask == nil else {
            statusMessage = "Daily fetch is already running."
            return
        }
        guard !isWorking else {
            statusMessage = "Wait for the current operation to finish before fetching."
            return
        }
        let profileIDs = queryProfiles.filter(\.isEnabled).map(\.id)
        guard !profileIDs.isEmpty else {
            statusMessage = "Enable at least one subscription before fetching."
            return
        }

        automationLastError = nil
        dailyFetchTask = Task { [weak self] in
            guard let self else { return }
            await self.performDailyFetch(profileIDs: profileIDs)
        }
    }

    func cancelActiveOperation() {
        guard dailyFetchTask != nil else { return }
        dailyFetchTask?.cancel()
        statusMessage = "Cancelling fetch…"
    }

    private func performDailyFetch(profileIDs: [QueryProfile.ID]) async {
        let startedAt = Date()
        activeOperation = ActiveOperationState(
            kind: .fetching,
            title: "Fetching subscriptions",
            detail: "Preparing arXiv requests",
            completedUnitCount: 0,
            totalUnitCount: profileIDs.count,
            startedAt: startedAt
        )
        var failures: [String] = []

        for (index, profileID) in profileIDs.enumerated() {
            if Task.isCancelled { break }
            let profileName = queryProfiles.first(where: { $0.id == profileID })?.name ?? "Subscription"
            activeOperation = ActiveOperationState(
                kind: .fetching,
                title: "Fetching · \(profileName)",
                detail: "\(index) of \(profileIDs.count) subscriptions complete",
                completedUnitCount: index,
                totalUnitCount: profileIDs.count,
                startedAt: startedAt
            )
            let succeeded = await fetchQuery(id: profileID)
            if !succeeded, !Task.isCancelled {
                failures.append(profileName)
            }
        }

        let wasCancelled = Task.isCancelled
        dailyFetchTask = nil
        activeOperation = nil
        if wasCancelled {
            statusMessage = "Daily fetch cancelled."
        } else if failures.isEmpty {
            automationLastError = nil
            statusMessage = "Daily fetch complete."
        } else {
            automationLastError = "Failed: \(failures.joined(separator: ", "))"
            statusMessage = automationLastError ?? "Daily fetch finished with errors."
        }
    }

    func runPendingJobs() async {
        await runPendingJobs(kind: nil)
    }

    func runPendingJobs(kind: SyncJob.Kind?) async {
        guard let store else { return }
        guard !isRunningJobs else {
            statusMessage = "The job runner is already active."
            return
        }
        isRunningJobs = true
        defer { isRunningJobs = false }
        await runBusy("Running jobs") {
            let configuration = try await makeAutomationConfiguration()
            try refreshJobCount()
            let processor = AutomationJobProcessor(store: store, configuration: configuration) { [weak self] in
                try self?.refreshJobCount()
            }
            let limit = try store.countJobs(kind: kind, state: .pending) + store.countJobs(kind: kind, state: .running)
            var result = try await processor.runPendingJobs(limit: max(1, limit), kind: kind)
            if result.succeeded > 0 || result.failed > 0 {
                try await drainFollowUpJobs(using: processor, into: &result)
            }
            papers = try store.fetchPapers()
            try refreshLatestAnalyses()
            try refreshJobCount()
            if result.succeeded > 0 || result.failed > 0 {
                statusMessage = "Jobs: \(result.succeeded) succeeded, \(result.failed) failed, \(result.skipped) skipped"
            } else if result.skipped > 0 {
                statusMessage = "Jobs skipped; missing configuration stays pending"
            } else {
                statusMessage = "No pending jobs were ready to run"
            }
        }
    }

    func runJob(jobID: SyncJob.ID) async {
        guard let store else { return }
        guard recentJobs.first(where: { $0.id == jobID })?.state != .running else {
            statusMessage = "That job is already running."
            return
        }
        await runBusy("Running selected job") {
            let configuration = try await makeAutomationConfiguration()
            let processor = AutomationJobProcessor(store: store, configuration: configuration) { [weak self] in
                try self?.refreshJobCount()
            }
            var result = try await processor.runJob(id: jobID)
            try await drainFollowUpJobs(using: processor, into: &result)
            papers = try store.fetchPapers()
            try refreshLatestAnalyses()
            try refreshJobCount()
            if result.succeeded > 0 {
                statusMessage = "Job completed"
            } else if result.failed > 0 {
                statusMessage = "Job failed"
            } else {
                statusMessage = "Job skipped"
            }
        }
    }

    func deleteJob(jobID: SyncJob.ID) {
        do {
            try store?.deleteJob(id: jobID)
            try refreshJobCount()
            statusMessage = "Job deleted"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func clearJobs(kind: SyncJob.Kind? = nil) {
        do {
            let deleted = try store?.deleteJobs(kind: kind, includingRunning: false) ?? 0
            try refreshJobCount()
            statusMessage = deleted == 1 ? "1 job cleared" : "\(deleted) jobs cleared"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func retryFailedJobs() {
        let failedIDs = failedJobs.map(\.id)
        guard !failedIDs.isEmpty else {
            statusMessage = "No failed jobs to retry."
            return
        }
        Task { [weak self] in
            guard let self else { return }
            for jobID in failedIDs {
                await self.runJob(jobID: jobID)
            }
        }
    }

    func createNotionDatabase() async {
        await runBusy("Creating Notion database") {
            saveSettings()
            guard !notionParentPageID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw AppActionError.missingNotionParentPage
            }
            guard let notionToken = try await keychainValue(for: "notion"), !notionToken.isEmpty else {
                throw AppActionError.missingNotionToken
            }
            let client = NotionAPIClient(config: NotionConfig(
                tokenRef: notionToken,
                parentPageID: notionParentPageID,
                databaseID: nil,
                dataSourceID: nil
            ))
            let request = try client.buildCreateDatabaseRequest()
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AutomationError.invalidHTTPResponse
            }
            guard (200..<300).contains(httpResponse.statusCode) else {
                throw AutomationError.httpFailure(httpResponse.statusCode, String(data: data, encoding: .utf8) ?? "")
            }
            guard let created = NotionResponseParser.createdDatabase(from: data) else {
                throw NotionError.invalidCreateDatabaseResponse
            }
            notionDatabaseID = created.databaseID
            notionDataSourceID = created.dataSourceID ?? ""
            saveSettings()
            statusMessage = created.dataSourceID == nil
                ? "Notion database created; paste the data source ID before syncing"
                : "Notion inline database created"
        }
    }

    func setBackgroundAutomaticFetchingEnabled(_ enabled: Bool) {
        configureBackgroundAutomaticFetching(enabled: enabled, force: false)
    }

    func repairBackgroundAutomaticFetching() {
        configureBackgroundAutomaticFetching(enabled: true, force: true)
    }

    private func configureBackgroundAutomaticFetching(enabled: Bool, force: Bool) {
        guard helperInstallTask == nil else {
            statusMessage = "Background automatic fetching is already being updated."
            return
        }
        guard force || enabled != backgroundAutomaticFetchingEnabled else { return }
        let helperURL = automationHelperURL
        if enabled, !FileManager.default.isExecutableFile(atPath: helperURL.path) {
            let error = AppActionError.helperNotFound(helperURL.path)
            launchAgentStatusError = error.localizedDescription
            automationLastError = error.localizedDescription
            statusMessage = error.localizedDescription
            return
        }
        let operationID = UUID()
        busyOperationIDs.insert(operationID)
        isWorking = true
        isUpdatingBackgroundAutomaticFetching = true
        statusMessage = enabled
            ? "Turning on background automatic fetching…"
            : "Turning off background automatic fetching…"
        helperInstallTask = Task { [weak self] in
            let snapshot = await Task.detached(priority: .userInitiated) {
                do {
                    let installer = LaunchAgentInstaller(helperExecutableURL: helperURL)
                    let status: LaunchAgentStatus
                    if enabled {
                        status = try installer.installAndLoad().status
                    } else {
                        status = try installer.uninstallAndUnload()
                    }
                    return AutomationInstallSnapshot(
                        status: status,
                        errorDescription: nil
                    )
                } catch {
                    return AutomationInstallSnapshot(
                        status: nil,
                        errorDescription: error.localizedDescription
                    )
                }
            }.value
            guard let self else { return }
            self.busyOperationIDs.remove(operationID)
            self.isWorking = !self.busyOperationIDs.isEmpty
            self.helperInstallTask = nil
            self.isUpdatingBackgroundAutomaticFetching = false
            if let status = snapshot.status {
                self.launchAgentStatus = status
                self.launchAgentStatusError = nil
                self.automationLastError = nil
                self.backgroundAutomaticFetchingEnabled = enabled
                self.defaults.set(enabled, forKey: DefaultsKey.backgroundAutomaticFetching)
                self.statusMessage = enabled
                    ? "Background automatic fetching is on."
                    : "Background automatic fetching is off; app-open checks remain active."
            } else {
                let message = snapshot.errorDescription ?? "Could not update background automatic fetching."
                self.launchAgentStatusError = message
                self.automationLastError = message
                self.statusMessage = message
                self.refreshAutomationStatus()
            }
        }
    }

    func refreshAutomationStatus() {
        guard automationStatusTask == nil else { return }
        let helperURL = automationHelperURL
        automationStatusTask = Task { [weak self] in
            let snapshot = await Task.detached(priority: .utility) {
                do {
                    return AutomationStatusSnapshot(
                        status: try LaunchAgentInstaller(helperExecutableURL: helperURL).status(),
                        errorDescription: nil
                    )
                } catch {
                    return AutomationStatusSnapshot(status: nil, errorDescription: error.localizedDescription)
                }
            }.value
            guard let self else { return }
            self.launchAgentStatus = snapshot.status
            self.launchAgentStatusError = snapshot.errorDescription
            if snapshot.status?.isLoaded == true, !self.backgroundAutomaticFetchingEnabled {
                self.backgroundAutomaticFetchingEnabled = true
                self.defaults.set(true, forKey: DefaultsKey.backgroundAutomaticFetching)
            }
            self.automationStatusTask = nil
        }
    }

    func saveProviderKey() {
        Task {
            await validateAndSaveProvider()
            startActiveAnalysisIfNeeded()
        }
    }

    func validateAndSaveProvider() async {
        await runBusy("Validating LLM") {
            guard let baseURL = URL(string: providerBaseURL) else {
                throw AppActionError.invalidProviderBaseURL
            }
            let effectiveKind = LLMProviderFactory.resolvedKind(for: providerKind, baseURL: baseURL)
            if effectiveKind == .azureOpenAI && azureDeploymentName(for: baseURL) == nil {
                throw AppActionError.missingAzureDeploymentName
            }
            let apiKey = providerAPIKeyDraft.isEmpty
                ? (try await storedProviderAPIKey(for: effectiveKind) ?? "")
                : providerAPIKeyDraft
            guard !apiKey.isEmpty else {
                throw AppActionError.missingProviderAPIKey
            }
            let provider = LLMProviderFactory.make(config: ProviderConfig(
                kind: effectiveKind,
                model: providerModel,
                baseURL: baseURL,
                apiKeyRef: effectiveKind.rawValue,
                apiVersion: providerAPIVersion,
                deploymentName: effectiveKind == .azureOpenAI ? azureDeploymentName(for: baseURL) : nil
            ))
            _ = try await provider.complete(
                apiKey: apiKey,
                payload: LLMPromptPayload(
                    system: "Return compact JSON only.",
                    user: #"Return exactly {"ok":true}."#,
                    temperature: 0,
                    maxTokens: 32,
                    expectsJSON: false
                )
            )
            providerKind = effectiveKind
            providerValidationFingerprint = RuntimeSettings.providerValidationFingerprint(
                kind: effectiveKind,
                model: providerModel,
                deploymentName: effectiveKind == .azureOpenAI ? azureDeploymentName(for: baseURL) ?? "" : "",
                baseURL: providerBaseURL,
                apiVersion: providerAPIVersion
            )
            try await setKeychainValue(apiKey, for: effectiveKind.rawValue)
            saveSettings()
            statusMessage = "LLM validated and saved"
        }
    }

    func saveNotionToken() {
        Task { await saveNotionTokenNow() }
    }

    private func saveNotionTokenNow() async {
        do {
            saveSettings()
            if !notionTokenDraft.isEmpty {
                try await setKeychainValue(notionTokenDraft, for: "notion")
            }
            notionTokenDraft = ""
            statusMessage = "Notion settings saved"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func saveZoteroToken() {
        Task { await saveZoteroTokenNow() }
    }

    private func saveZoteroTokenNow() async {
        do {
            saveSettings()
            if !zoteroTokenDraft.isEmpty {
                try await setKeychainValue(zoteroTokenDraft, for: "zotero")
            }
            zoteroTokenDraft = ""
            statusMessage = "Zotero settings saved"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func saveSettings() {
        let settings = currentRuntimeSettings()
        try? runtimeSettingsStore?.save(settings)
        defaults.set(providerKind.rawValue, forKey: DefaultsKey.providerKind)
        defaults.set(providerModel, forKey: DefaultsKey.providerModel)
        defaults.set(providerDeploymentName, forKey: DefaultsKey.providerDeploymentName)
        defaults.set(providerBaseURL, forKey: DefaultsKey.providerBaseURL)
        defaults.set(providerAPIVersion, forKey: DefaultsKey.providerAPIVersion)
        defaults.set(providerMaxTokens, forKey: DefaultsKey.providerMaxTokens)
        defaults.set(providerTemperature, forKey: DefaultsKey.providerTemperature)
        if let topP = parsedProviderTopP {
            defaults.set(topP, forKey: DefaultsKey.providerTopP)
        } else {
            defaults.removeObject(forKey: DefaultsKey.providerTopP)
        }
        defaults.set(providerConcurrency, forKey: DefaultsKey.providerConcurrency)
        defaults.set(providerRetryLimit, forKey: DefaultsKey.providerRetryLimit)
        defaults.set(notionParentPageID, forKey: DefaultsKey.notionParentPageID)
        defaults.set(notionDatabaseID, forKey: DefaultsKey.notionDatabaseID)
        defaults.set(notionDataSourceID, forKey: DefaultsKey.notionDataSourceID)
        defaults.set(notionAutoSync, forKey: DefaultsKey.notionAutoSync)
        defaults.set(activeAnalyzeUnanalyzedPapers, forKey: DefaultsKey.activeAnalyzeUnanalyzedPapers)
        defaults.set(zoteroLibraryKind, forKey: DefaultsKey.zoteroLibraryKind)
        defaults.set(zoteroLibraryID, forKey: DefaultsKey.zoteroLibraryID)
        defaults.set(zoteroCollectionKey, forKey: DefaultsKey.zoteroCollectionKey)
        defaults.set(academicProfileInput, forKey: DefaultsKey.academicProfileInput)
        defaults.set(generatedAcademicProfile, forKey: DefaultsKey.generatedAcademicProfile)
        defaults.set(summaryLanguage.rawValue, forKey: DefaultsKey.summaryLanguage)
        defaults.set(summaryPromptInstructions, forKey: DefaultsKey.summaryPromptInstructions)
        defaults.set(deepReadPrompt, forKey: DefaultsKey.deepReadPrompt)
    }

    func updateQueryPreview() {
        guard let query = selectedQuery() else {
            queryPreviewURL = ""
            return
        }
        let request = ArxivAPIRequest(searchQuery: .raw(query.requestRawQuery), maxResults: query.maxResults)
        queryPreviewURL = (try? request.url().absoluteString) ?? "Invalid query"
    }

    private func update(_ paper: Paper) {
        do {
            try store?.upsertPaper(paper)
            if let index = papers.firstIndex(where: { $0.id == paper.id }) {
                papers[index] = paper
            }
            if let index = briefingPapers.firstIndex(where: { $0.id == paper.id }) {
                briefingPapers[index] = paper
            }
            savedPaperCount = papers.lazy.filter { $0.status == .interested }.count
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func refreshLatestAnalyses() throws {
        guard let store else {
            latestAnalysesByPaperID = [:]
            latestDeepReadsByPaperID = [:]
            return
        }
        latestAnalysesByPaperID = try store.fetchLatestAnalyses()
        latestDeepReadsByPaperID = try store.fetchLatestDeepReads()
        rebuildBriefingPapers()
    }

    private func rebuildBriefingPapers() {
        savedPaperCount = papers.lazy.filter { $0.status == .interested }.count
        recentPapers = papers.sorted {
            ($0.addedAt ?? $0.updatedAt ?? $0.publishedAt ?? .distantPast)
                > ($1.addedAt ?? $1.updatedAt ?? $1.publishedAt ?? .distantPast)
        }
        briefingPapers = papers.sorted { lhs, rhs in
            let lhsScore = latestAnalysesByPaperID[lhs.arxivID]?.relevanceScore ?? -1
            let rhsScore = latestAnalysesByPaperID[rhs.arxivID]?.relevanceScore ?? -1
            if lhsScore != rhsScore {
                return lhsScore > rhsScore
            }
            return (lhs.addedAt ?? lhs.updatedAt ?? lhs.publishedAt ?? .distantPast)
                > (rhs.addedAt ?? rhs.updatedAt ?? rhs.publishedAt ?? .distantPast)
        }
    }

    private func refreshJobCount() throws {
        try store?.recoverStaleRunningJobs()
        pendingJobCount = try store?.countJobs(state: .pending) ?? 0
        recentJobs = try store?.fetchJobs(limit: 40) ?? []
    }

    private func startQueuedJobsIfIdle() {
        guard !isAutoRunScheduled else {
            return
        }
        guard !isWorking else {
            needsQueuedJobDrain = true
            return
        }
        needsQueuedJobDrain = false
        isAutoRunScheduled = true
        Task { [weak self] in
            await self?.runAutoQueuedJobs()
        }
    }

    private func startActiveAnalysisIfNeeded() {
        guard activeAnalyzeUnanalyzedPapers,
              currentRuntimeSettings().canQueueSummariesWithoutSecrets,
              !isWorking,
              !isAutoRunScheduled
        else {
            return
        }
        isAutoRunScheduled = true
        Task { [weak self] in
            defer { Task { @MainActor in self?.isAutoRunScheduled = false } }
            await self?.analyzeUnanalyzedPapersNow()
        }
    }

    private func runAutoQueuedJobs() async {
        defer { isAutoRunScheduled = false }
        await runPendingJobs()
    }

    private func drainFollowUpJobs(
        using processor: AutomationJobProcessor,
        into result: inout AutomationJobRunResult
    ) async throws {
        guard let store else {
            return
        }
        let limit = try store.countJobs(state: .pending)
        guard limit > 0 else {
            return
        }
        let followUpResult = try await processor.runPendingJobs(limit: max(20, limit * 2 + 10), kind: nil)
        result.succeeded += followUpResult.succeeded
        result.failed += followUpResult.failed
    }

    private func runBusy(_ workingMessage: String, operation: () async throws -> Void) async {
        let operationID = UUID()
        busyOperationIDs.insert(operationID)
        isWorking = !busyOperationIDs.isEmpty
        statusMessage = workingMessage
        defer {
            busyOperationIDs.remove(operationID)
            isWorking = !busyOperationIDs.isEmpty
            if !isWorking, needsQueuedJobDrain, !isAutoRunScheduled {
                startQueuedJobsIfIdle()
            }
        }
        do {
            try await operation()
        } catch is CancellationError {
            statusMessage = "Operation cancelled."
        } catch {
            statusMessage = error.localizedDescription
            automationLastError = error.localizedDescription
        }
    }

    private func validatedSidebarSelection(_ selection: LibrarySidebarSelection) -> LibrarySidebarSelection {
        switch selection {
        case .all, .thisWeek, .date:
            selection
        case let .query(id):
            queryProfiles.contains(where: { $0.id == id }) ? selection : .all
        }
    }

    private func loadSettings() {
        if let settings = try? runtimeSettingsStore?.load() {
            apply(settings)
            return
        }
        apply(RuntimeSettings(
            providerKind: ProviderKind(rawValue: defaults.string(forKey: DefaultsKey.providerKind) ?? "") ?? .openAI,
            providerModel: defaults.string(forKey: DefaultsKey.providerModel) ?? providerModel,
            providerDeploymentName: defaults.string(forKey: DefaultsKey.providerDeploymentName) ?? providerDeploymentName,
            providerBaseURL: defaults.string(forKey: DefaultsKey.providerBaseURL) ?? providerBaseURL,
            providerAPIVersion: defaults.string(forKey: DefaultsKey.providerAPIVersion) ?? providerAPIVersion,
            providerMaxTokens: defaults.object(forKey: DefaultsKey.providerMaxTokens) as? Int ?? providerMaxTokens,
            providerTemperature: defaults.object(forKey: DefaultsKey.providerTemperature) as? Double ?? providerTemperature,
            providerTopP: defaults.object(forKey: DefaultsKey.providerTopP) as? Double,
            providerConcurrency: defaults.object(forKey: DefaultsKey.providerConcurrency) as? Int ?? providerConcurrency,
            providerRetryLimit: defaults.object(forKey: DefaultsKey.providerRetryLimit) as? Int ?? providerRetryLimit,
            notionParentPageID: defaults.string(forKey: DefaultsKey.notionParentPageID) ?? "",
            notionDatabaseID: defaults.string(forKey: DefaultsKey.notionDatabaseID) ?? "",
            notionDataSourceID: defaults.string(forKey: DefaultsKey.notionDataSourceID) ?? "",
            notionAutoSync: defaults.bool(forKey: DefaultsKey.notionAutoSync),
            activeAnalyzeUnanalyzedPapers: defaults.object(forKey: DefaultsKey.activeAnalyzeUnanalyzedPapers) as? Bool ?? true,
            zoteroLibraryKind: defaults.string(forKey: DefaultsKey.zoteroLibraryKind) ?? "user",
            zoteroLibraryID: defaults.string(forKey: DefaultsKey.zoteroLibraryID) ?? "",
            zoteroCollectionKey: defaults.string(forKey: DefaultsKey.zoteroCollectionKey) ?? "",
            academicProfileInput: defaults.string(forKey: DefaultsKey.academicProfileInput) ?? "",
            generatedAcademicProfile: defaults.string(forKey: DefaultsKey.generatedAcademicProfile) ?? "",
            summaryLanguage: SummaryLanguage(rawValue: defaults.string(forKey: DefaultsKey.summaryLanguage) ?? "") ?? .english,
            summaryPromptInstructions: defaults.string(forKey: DefaultsKey.summaryPromptInstructions) ?? DefaultPrompts.summaryInstructions,
            deepReadPrompt: defaults.string(forKey: DefaultsKey.deepReadPrompt) ?? DefaultPrompts.deepRead
        ))
    }

    private func currentRuntimeSettings() -> RuntimeSettings {
        RuntimeSettings(
            providerKind: providerKind,
            providerModel: providerModel,
            providerDeploymentName: providerDeploymentName,
            providerBaseURL: providerBaseURL,
            providerAPIVersion: providerAPIVersion,
            providerMaxTokens: providerMaxTokens,
            providerTemperature: providerTemperature,
            providerTopP: parsedProviderTopP,
            providerConcurrency: providerConcurrency,
            providerRetryLimit: providerRetryLimit,
            providerValidationFingerprint: providerValidationFingerprint,
            notionParentPageID: notionParentPageID,
            notionDatabaseID: notionDatabaseID,
            notionDataSourceID: notionDataSourceID,
            notionAutoSync: notionAutoSync,
            activeAnalyzeUnanalyzedPapers: activeAnalyzeUnanalyzedPapers,
            zoteroLibraryKind: zoteroLibraryKind,
            zoteroLibraryID: zoteroLibraryID,
            zoteroCollectionKey: zoteroCollectionKey,
            academicProfileInput: academicProfileInput,
            generatedAcademicProfile: generatedAcademicProfile,
            summaryLanguage: summaryLanguage,
            summaryPromptInstructions: summaryPromptInstructions,
            deepReadPrompt: deepReadPrompt
        )
    }

    private func apply(_ settings: RuntimeSettings) {
        providerModel = settings.providerModel
        providerBaseURL = settings.providerBaseURL
        if let baseURL = URL(string: settings.providerBaseURL) {
            providerKind = LLMProviderFactory.resolvedKind(for: settings.providerKind, baseURL: baseURL)
            providerDeploymentName = settings.providerDeploymentName.nilIfEmpty
                ?? extractedAzureDeploymentName(from: baseURL)
                ?? (providerKind == .azureOpenAI ? settings.providerModel : "")
        } else {
            providerKind = settings.providerKind
            providerDeploymentName = settings.providerDeploymentName
        }
        providerAPIVersion = settings.providerAPIVersion
        providerMaxTokens = settings.providerMaxTokens
        providerTemperature = settings.providerTemperature
        providerTopPText = settings.providerTopP.map { Self.formatNumber($0) } ?? ""
        providerConcurrency = settings.providerConcurrency
        providerRetryLimit = settings.providerRetryLimit
        providerValidationFingerprint = settings.providerValidationFingerprint
        notionParentPageID = settings.notionParentPageID
        notionDatabaseID = settings.notionDatabaseID
        notionDataSourceID = settings.notionDataSourceID
        notionAutoSync = settings.notionAutoSync
        activeAnalyzeUnanalyzedPapers = settings.activeAnalyzeUnanalyzedPapers
        zoteroLibraryKind = settings.zoteroLibraryKind
        zoteroLibraryID = settings.zoteroLibraryID
        zoteroCollectionKey = settings.zoteroCollectionKey
        academicProfileInput = settings.academicProfileInput
        generatedAcademicProfile = settings.generatedAcademicProfile
        summaryLanguage = settings.summaryLanguage
        summaryPromptInstructions = settings.summaryPromptInstructions
        deepReadPrompt = settings.deepReadPrompt
    }

    private func makeAutomationConfiguration() async throws -> AutomationConfiguration {
        let settings = currentRuntimeSettings()
        var llmProvider: (any LLMProvider)?
        var llmAPIKey: String?
        if let baseURL = URL(string: settings.providerBaseURL),
           let apiKey = try await storedProviderAPIKey(for: LLMProviderFactory.resolvedKind(for: settings.providerKind, baseURL: baseURL)),
           !apiKey.isEmpty {
            let effectiveKind = LLMProviderFactory.resolvedKind(for: settings.providerKind, baseURL: baseURL)
            let deploymentName = effectiveKind == .azureOpenAI
                ? extractedAzureDeploymentName(from: baseURL) ?? settings.providerDeploymentName.nilIfEmpty
                : nil
            if effectiveKind != .azureOpenAI || deploymentName != nil {
                let config = ProviderConfig(
                    kind: effectiveKind,
                    model: settings.providerModel,
                    baseURL: baseURL,
                    apiKeyRef: effectiveKind.rawValue,
                    apiVersion: settings.providerAPIVersion,
                    deploymentName: deploymentName
                )
                llmProvider = LLMProviderFactory.make(config: config)
                llmAPIKey = apiKey
            }
        }

        var notionClient: (any NotionSyncClient)?
        if let notionToken = try await keychainValue(for: "notion"),
           !notionToken.isEmpty,
           !settings.notionDataSourceID.isEmpty {
            notionClient = NotionAPIClient(config: NotionConfig(
                tokenRef: notionToken,
                parentPageID: settings.notionParentPageID,
                databaseID: settings.notionDatabaseID.isEmpty ? nil : settings.notionDatabaseID,
                dataSourceID: settings.notionDataSourceID
            ))
        }

        var zoteroClient: (any ZoteroSyncClient)?
        if let zoteroToken = try await keychainValue(for: "zotero"),
           !zoteroToken.isEmpty,
           let libraryID = Int(settings.zoteroLibraryID),
           !settings.zoteroCollectionKey.isEmpty {
            let library: ZoteroConfig.Library = settings.zoteroLibraryKind == "group" ? .group(id: libraryID) : .user(id: libraryID)
            zoteroClient = ZoteroAPIClient(config: ZoteroConfig(
                tokenRef: zoteroToken,
                library: library,
                collectionKey: settings.zoteroCollectionKey
            ))
        }

        return AutomationConfiguration(
            llmProvider: llmProvider,
            llmAPIKey: llmAPIKey,
            summaryPromptOptions: SummaryPromptOptions(
                academicProfile: settings.generatedAcademicProfile,
                language: settings.summaryLanguage,
                customInstructions: settings.summaryPromptInstructions
            ),
            deepReadPrompt: settings.deepReadPrompt,
            llmMaxTokens: settings.providerMaxTokens,
            llmTemperature: settings.providerTemperature,
            llmTopP: settings.providerTopP,
            llmConcurrency: settings.providerConcurrency,
            llmRetryLimit: settings.providerRetryLimit,
            notionClient: notionClient,
            zoteroClient: zoteroClient,
            autoSyncNotion: settings.notionAutoSync,
            activeAnalyzeUnanalyzedPapers: settings.activeAnalyzeUnanalyzedPapers
        )
    }

    private func storedProviderAPIKey(for kind: ProviderKind) async throws -> String? {
        if let direct = try await keychainValue(for: kind.rawValue), !direct.isEmpty {
            return direct
        }
        if kind == .azureOpenAI,
           let legacyOpenAIKey = try await keychainValue(for: ProviderKind.openAI.rawValue),
           !legacyOpenAIKey.isEmpty {
            return legacyOpenAIKey
        }
        return nil
    }

    private func keychainValue(for key: String) async throws -> String? {
        let service = keychain.service
        return try await Task.detached(priority: .userInitiated) {
            try KeychainStore(service: service).get(key)
        }.value
    }

    private func setKeychainValue(_ value: String, for key: String) async throws {
        let service = keychain.service
        try await Task.detached(priority: .userInitiated) {
            try KeychainStore(service: service).set(value, for: key)
        }.value
    }

    private func azureDeploymentName(for baseURL: URL) -> String? {
        extractedAzureDeploymentName(from: baseURL) ?? providerDeploymentName.nilIfEmpty
    }

    private var parsedProviderTopP: Double? {
        let value = providerTopPText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, let topP = Double(value), topP > 0, topP <= 1 else {
            return nil
        }
        return topP
    }

    private func completeLLM(provider: any LLMProvider, apiKey: String, payload: LLMPromptPayload, retryLimit: Int) async throws -> String {
        var lastError: Error?
        for attempt in 0...max(0, retryLimit) {
            do {
                return try await provider.complete(apiKey: apiKey, payload: payload)
            } catch {
                lastError = error
                guard attempt < retryLimit else { break }
                try await Task.sleep(for: .milliseconds(250 * UInt64(attempt + 1)))
            }
        }
        throw lastError ?? LLMProviderError.invalidResponse
    }

    private static func formatNumber(_ value: Double) -> String {
        let rounded = (value * 1000).rounded() / 1000
        return String(rounded)
    }

    private func extractedAzureDeploymentName(from baseURL: URL) -> String? {
        let components = baseURL.pathComponents
        guard let deploymentsIndex = components.firstIndex(where: { $0.lowercased() == "deployments" }),
              components.indices.contains(deploymentsIndex + 1)
        else {
            return nil
        }
        return components[deploymentsIndex + 1].removingPercentEncoding?.nilIfEmpty
    }

    private func missingConfigurationMessage(for kind: SyncJob.Kind) -> String {
        switch kind {
        case .summarizeAbstract:
            "Validate LLM settings before queuing summaries."
        case .deepRead:
            "Validate LLM settings before queuing deep reads."
        case .syncNotion:
            "Save Notion token and data source ID before queuing sync."
        case .syncZotero:
            "Save Zotero token, library ID, and collection key before queuing sync."
        case .fetchArxiv:
            "arXiv fetch does not require extra configuration."
        }
    }

    private func seedPreviewData() {
        papers = [
            Paper.fixture(arxivID: "2401.00001"),
            Paper.fixture(arxivID: "2401.00002")
        ]
        rebuildBriefingPapers()
        selectedPaperID = papers.first?.id
    }

    private func sidebarSelection(for filter: PaperLibraryDateFilter) -> LibrarySidebarSelection {
        switch filter {
        case .all:
            .all
        case let .day(field, date):
            .date(field, date)
        case let .thisWeek(field, _):
            .thisWeek(field)
        }
    }
}

private enum DefaultsKey {
    static let backgroundAutomaticFetching = "automation.backgroundAutomaticFetching"
    static let providerKind = "provider.kind"
    static let providerModel = "provider.model"
    static let providerDeploymentName = "provider.deploymentName"
    static let providerBaseURL = "provider.baseURL"
    static let providerAPIVersion = "provider.apiVersion"
    static let providerMaxTokens = "provider.maxTokens"
    static let providerTemperature = "provider.temperature"
    static let providerTopP = "provider.topP"
    static let providerConcurrency = "provider.concurrency"
    static let providerRetryLimit = "provider.retryLimit"
    static let notionParentPageID = "notion.parentPageID"
    static let notionDatabaseID = "notion.databaseID"
    static let notionDataSourceID = "notion.dataSourceID"
    static let notionAutoSync = "notion.autoSync"
    static let activeAnalyzeUnanalyzedPapers = "analysis.activeAnalyzeUnanalyzedPapers"
    static let zoteroLibraryKind = "zotero.libraryKind"
    static let zoteroLibraryID = "zotero.libraryID"
    static let zoteroCollectionKey = "zotero.collectionKey"
    static let academicProfileInput = "analysis.academicProfileInput"
    static let generatedAcademicProfile = "analysis.generatedAcademicProfile"
    static let summaryLanguage = "analysis.summaryLanguage"
    static let summaryPromptInstructions = "analysis.summaryPromptInstructions"
    static let deepReadPrompt = "deepRead.prompt"
}

private enum AppActionError: Error, LocalizedError {
    case missingNotionParentPage
    case missingNotionToken
    case helperNotFound(String)
    case invalidProviderBaseURL
    case missingProviderAPIKey
    case missingAzureDeploymentName
    case missingAcademicProfileInput
    case missingLLMForProfile

    var errorDescription: String? {
        switch self {
        case .missingNotionParentPage:
            "Notion parent page ID is required."
        case .missingNotionToken:
            "Save a Notion token first."
        case let .helperNotFound(path):
            "Helper executable was not found at \(path)."
        case .invalidProviderBaseURL:
            "LLM base URL is invalid."
        case .missingProviderAPIKey:
            "Enter an API key or keep a previously saved key for this provider."
        case .missingAzureDeploymentName:
            "Azure OpenAI requires a deployment name or a base URL containing /openai/deployments/<deployment>."
        case .missingAcademicProfileInput:
            "Enter papers, abstracts, keywords, or research notes before generating an academic profile."
        case .missingLLMForProfile:
            "Validate LLM settings before generating an academic profile."
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
