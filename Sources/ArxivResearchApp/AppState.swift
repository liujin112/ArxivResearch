import Foundation
import SwiftUI
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

@MainActor
final class AppState: ObservableObject {
    @Published var queryProfiles: [QueryProfile] = []
    @Published var papers: [Paper] = []
    @Published var sidebarSelection: LibrarySidebarSelection = .all
    @Published var libraryDateField: PaperDateField = .added
    @Published var selectedQueryID: QueryProfile.ID?
    @Published var selectedPaperID: Paper.ID?
    @Published var selectedPaperAnalysis: LLMAnalysis?
    @Published var latestAnalysesByPaperID: [String: LLMAnalysis] = [:]
    @Published var deepReadMarkdown = ""
    @Published var statusMessage = "Ready"
    @Published var pendingJobCount = 0
    @Published var recentJobs: [SyncJob] = []
    @Published var isWorking = false
    @Published var queryPreviewURL = ""

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
    private let renderer = MarkdownHTMLRenderer()
    private let defaults = UserDefaults.standard
    private let runtimeSettingsStore = try? RuntimeSettingsStore.default()

    var selectedPaper: Paper? {
        papers.first { $0.id == selectedPaperID }
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

    var renderedPaperDetailHTML: String {
        renderer.render(selectedPaperDetailMarkdown)
    }

    var renderedDeepReadHTML: String {
        renderedPaperDetailHTML
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

    private var selectedPaperDetailMarkdown: String {
        var markdown = selectedPaperMarkdown
        let deepRead = deepReadMarkdown.trimmingCharacters(in: .whitespacesAndNewlines)
        if !deepRead.isEmpty {
            markdown += "\n\n---\n\n## Deep Read\n\n\(deepRead)\n"
        }
        return markdown
    }

    private var selectedPaperMarkdown: String {
        guard let paper = selectedPaper else {
            return "# No Paper Selected\n\nChoose a paper from the list."
        }
        var markdown = "# \(paper.title)\n\n"
        markdown += "**Authors:** \(paper.authors.joined(separator: ", "))\n\n"
        markdown += "**arXiv:** \(paper.arxivID)\n\n"
        markdown += "## Abstract\n\n\(paper.abstract)\n\n"
        if let analysis = selectedPaperAnalysis {
            markdown += "**Score:** \(RelevanceScore.displayScore(analysis.relevanceScore))/100\n\n"
            markdown += "## LLM Summary\n\n\(analysis.oneSentenceSummary)\n\n"
            markdown += "### Why It Matters\n\n\(analysis.rationale)\n"
        }
        return markdown
    }

    init() {
        loadSettings()
        do {
            let dbURL = try AppEnvironment.defaultDatabaseURL()
            store = try SQLiteResearchStore(path: dbURL)
            try load()
        } catch {
            statusMessage = "Local store unavailable: \(error.localizedDescription)"
            seedPreviewData()
        }
    }

    func load() throws {
        guard let store else { return }
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
        selectedQueryID = queryProfiles.first?.id
        sidebarSelection = .all
        selectedPaperID = papers.first?.id
        try refreshJobCount()
        updateQueryPreview()
        try loadSelectedAnalysis()
    }

    func reload() {
        do {
            try load()
            statusMessage = "Reloaded local data"
        } catch {
            statusMessage = error.localizedDescription
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
            if let selectedPaperID, !papers.contains(where: { $0.id == selectedPaperID }) {
                self.selectedPaperID = papers.first?.id
                try loadSelectedAnalysis()
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

    func selectPaper(_ paper: Paper) {
        selectedPaperID = paper.id
        do {
            try loadSelectedAnalysis()
        } catch {
            statusMessage = error.localizedDescription
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
        guard papers.contains(where: { $0.id == paperID }) else { return }
        do {
            guard try makeAutomationConfiguration().canProcess(.summarizeAbstract) else {
                statusMessage = missingConfigurationMessage(for: .summarizeAbstract)
                return
            }
            try store?.enqueue(SyncJob(kind: .summarizeAbstract, payload: Data(paperID.utf8)))
            try refreshJobCount()
            statusMessage = "Abstract analysis queued for \(paperID)"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func queueDeepRead() {
        guard let paper = selectedPaper else { return }
        queueDeepRead(paperID: paper.arxivID)
    }

    func queueDeepRead(paperID: Paper.ID) {
        guard var paper = papers.first(where: { $0.id == paperID }) else { return }
        do {
            guard try makeAutomationConfiguration().canProcess(.deepRead) else {
                statusMessage = missingConfigurationMessage(for: .deepRead)
                return
            }
            paper.status = .deepReading
            try store?.upsertPaper(paper)
            if let index = papers.firstIndex(where: { $0.id == paperID }) {
                papers[index] = paper
            }
            try store?.enqueue(SyncJob(kind: .deepRead, payload: Data(paperID.utf8)))
            try refreshJobCount()
            statusMessage = "Deep read queued for \(paperID). Check Jobs, then run pending jobs or wait for Helper."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func syncNotion() {
        guard let paper = selectedPaper else { return }
        syncNotion(paperID: paper.arxivID)
    }

    func syncNotion(paperID: Paper.ID) {
        do {
            guard try makeAutomationConfiguration().canProcess(.syncNotion) else {
                statusMessage = missingConfigurationMessage(for: .syncNotion)
                return
            }
            try store?.enqueue(SyncJob(kind: .syncNotion, payload: Data(paperID.utf8)))
            try refreshJobCount()
            statusMessage = "Notion sync queued"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func syncZotero() {
        guard let paper = selectedPaper else { return }
        syncZotero(paperID: paper.arxivID)
    }

    func syncZotero(paperID: Paper.ID) {
        do {
            guard try makeAutomationConfiguration().canProcess(.syncZotero) else {
                statusMessage = missingConfigurationMessage(for: .syncZotero)
                return
            }
            try store?.enqueue(SyncJob(kind: .syncZotero, payload: Data(paperID.utf8)))
            try refreshJobCount()
            statusMessage = "Zotero sync queued"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func deletePaper(paperID: Paper.ID) {
        do {
            try store?.deletePaper(arxivID: paperID)
            papers.removeAll { $0.id == paperID }
            latestAnalysesByPaperID.removeValue(forKey: paperID)
            if selectedPaperID == paperID {
                selectedPaperID = papers.first?.id
                try loadSelectedAnalysis()
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
            let configuration = try makeAutomationConfiguration()
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

    func fetchQuery(id: QueryProfile.ID) async {
        guard var profile = queryProfiles.first(where: { $0.id == id }), let store else { return }
        selectedQueryID = id
        await runBusy("Fetching arXiv") {
            let shouldQueueSummaries = currentRuntimeSettings().canQueueSummariesWithoutSecrets
            let request = ArxivAPIRequest(searchQuery: .raw(profile.requestRawQuery), maxResults: profile.maxResults)
            queryPreviewURL = try request.url().absoluteString
            let feed = try await ArxivHTTPClient().search(request)
            let fetchedAt = Date()
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
                if shouldQueueSummaries {
                    try store.enqueue(SyncJob(kind: .summarizeAbstract, payload: Data(entry.arxivID.utf8)))
                }
            }
            profile.lastFetchedAt = Date()
            try store.upsertQueryProfile(profile)
            queryProfiles = try store.fetchQueryProfiles()
            papers = try store.fetchPapers()
            try refreshLatestAnalyses()
            selectedPaperID = papers.first?.id
            try refreshJobCount()
            try loadSelectedAnalysis()
            statusMessage = shouldQueueSummaries
                ? "Fetched \(feed.entries.count) papers and queued summaries"
                : "Fetched \(feed.entries.count) papers; validate LLM before queuing summaries"
        }
    }

    func runPendingJobs() async {
        await runPendingJobs(kind: nil)
    }

    func runPendingJobs(kind: SyncJob.Kind?) async {
        guard let store else { return }
        await runBusy("Running jobs") {
            let configuration = try makeAutomationConfiguration()
            try refreshJobCount()
            let processor = AutomationJobProcessor(store: store, configuration: configuration) { [weak self] in
                try self?.refreshJobCount()
            }
            let limit = try store.countJobs(kind: kind, state: .pending)
            let result = try await processor.runPendingJobs(limit: max(1, limit), kind: kind)
            papers = try store.fetchPapers()
            try refreshLatestAnalyses()
            try refreshJobCount()
            try loadSelectedAnalysis()
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
        await runBusy("Running selected job") {
            let configuration = try makeAutomationConfiguration()
            let processor = AutomationJobProcessor(store: store, configuration: configuration) { [weak self] in
                try self?.refreshJobCount()
            }
            let result = try await processor.runJob(id: jobID)
            papers = try store.fetchPapers()
            try refreshLatestAnalyses()
            try refreshJobCount()
            try loadSelectedAnalysis()
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
            let deleted = try store?.deleteJobs(kind: kind) ?? 0
            try refreshJobCount()
            statusMessage = deleted == 1 ? "1 job cleared" : "\(deleted) jobs cleared"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func createNotionDatabase() async {
        await runBusy("Creating Notion database") {
            saveSettings()
            guard !notionParentPageID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw AppActionError.missingNotionParentPage
            }
            guard let notionToken = try keychain.get("notion"), !notionToken.isEmpty else {
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

    func installLaunchAgent() {
        do {
            let helperURL = Bundle.main.bundleURL
                .appendingPathComponent("Contents", isDirectory: true)
                .appendingPathComponent("Helpers", isDirectory: true)
                .appendingPathComponent("ArxivResearchHelper")
            guard FileManager.default.isExecutableFile(atPath: helperURL.path) else {
                throw AppActionError.helperNotFound(helperURL.path)
            }
            let destination = try LaunchAgentInstaller(helperExecutableURL: helperURL).install()
            statusMessage = "LaunchAgent installed: \(destination.lastPathComponent)"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func saveProviderKey() {
        Task { await validateAndSaveProvider() }
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
                ? (try storedProviderAPIKey(for: effectiveKind) ?? "")
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
            try keychain.set(apiKey, for: effectiveKind.rawValue)
            saveSettings()
            statusMessage = "LLM validated and saved"
        }
    }

    func saveNotionToken() {
        do {
            saveSettings()
            if !notionTokenDraft.isEmpty {
                try keychain.set(notionTokenDraft, for: "notion")
            }
            notionTokenDraft = ""
            statusMessage = "Notion settings saved"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func saveZoteroToken() {
        do {
            saveSettings()
            if !zoteroTokenDraft.isEmpty {
                try keychain.set(zoteroTokenDraft, for: "zotero")
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
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func loadSelectedAnalysis() throws {
        guard let id = selectedPaperID else {
            selectedPaperAnalysis = nil
            deepReadMarkdown = ""
            return
        }
        selectedPaperAnalysis = try store?.latestAnalysis(for: id)
        deepReadMarkdown = try store?.latestDeepRead(for: id)?.markdown ?? ""
    }

    private func refreshLatestAnalyses() throws {
        guard let store else {
            latestAnalysesByPaperID = [:]
            return
        }
        latestAnalysesByPaperID = try Dictionary(
            uniqueKeysWithValues: papers.compactMap { paper in
                guard let analysis = try store.latestAnalysis(for: paper.arxivID) else {
                    return nil
                }
                return (paper.arxivID, analysis)
            }
        )
    }

    private func refreshJobCount() throws {
        pendingJobCount = try store?.countJobs(state: .pending) ?? 0
        recentJobs = try store?.fetchJobs(limit: 40) ?? []
    }

    private func runBusy(_ workingMessage: String, operation: () async throws -> Void) async {
        isWorking = true
        statusMessage = workingMessage
        defer { isWorking = false }
        do {
            try await operation()
        } catch {
            statusMessage = error.localizedDescription
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
        zoteroLibraryKind = settings.zoteroLibraryKind
        zoteroLibraryID = settings.zoteroLibraryID
        zoteroCollectionKey = settings.zoteroCollectionKey
        academicProfileInput = settings.academicProfileInput
        generatedAcademicProfile = settings.generatedAcademicProfile
        summaryLanguage = settings.summaryLanguage
        summaryPromptInstructions = settings.summaryPromptInstructions
        deepReadPrompt = settings.deepReadPrompt
    }

    private func makeAutomationConfiguration() throws -> AutomationConfiguration {
        var llmProvider: (any LLMProvider)?
        var llmAPIKey: String?
        if let baseURL = URL(string: providerBaseURL),
           let apiKey = try storedProviderAPIKey(for: LLMProviderFactory.resolvedKind(for: providerKind, baseURL: baseURL)),
           !apiKey.isEmpty {
            let effectiveKind = LLMProviderFactory.resolvedKind(for: providerKind, baseURL: baseURL)
            let deploymentName = effectiveKind == .azureOpenAI ? azureDeploymentName(for: baseURL) : nil
            if effectiveKind != .azureOpenAI || deploymentName != nil {
                let config = ProviderConfig(
                    kind: effectiveKind,
                    model: providerModel,
                    baseURL: baseURL,
                    apiKeyRef: effectiveKind.rawValue,
                    apiVersion: providerAPIVersion,
                    deploymentName: deploymentName
                )
                llmProvider = LLMProviderFactory.make(config: config)
                llmAPIKey = apiKey
            }
        }

        var notionClient: (any NotionSyncClient)?
        if let notionToken = try keychain.get("notion"),
           !notionToken.isEmpty,
           !notionDataSourceID.isEmpty {
            notionClient = NotionAPIClient(config: NotionConfig(
                tokenRef: notionToken,
                parentPageID: notionParentPageID,
                databaseID: notionDatabaseID.isEmpty ? nil : notionDatabaseID,
                dataSourceID: notionDataSourceID
            ))
        }

        var zoteroClient: (any ZoteroSyncClient)?
        if let zoteroToken = try keychain.get("zotero"),
           !zoteroToken.isEmpty,
           let libraryID = Int(zoteroLibraryID),
           !zoteroCollectionKey.isEmpty {
            let library: ZoteroConfig.Library = zoteroLibraryKind == "group" ? .group(id: libraryID) : .user(id: libraryID)
            zoteroClient = ZoteroAPIClient(config: ZoteroConfig(
                tokenRef: zoteroToken,
                library: library,
                collectionKey: zoteroCollectionKey
            ))
        }

        return AutomationConfiguration(
            llmProvider: llmProvider,
            llmAPIKey: llmAPIKey,
            summaryPromptOptions: SummaryPromptOptions(
                academicProfile: generatedAcademicProfile,
                language: summaryLanguage,
                customInstructions: summaryPromptInstructions
            ),
            deepReadPrompt: deepReadPrompt,
            llmMaxTokens: providerMaxTokens,
            llmTemperature: providerTemperature,
            llmTopP: parsedProviderTopP,
            llmConcurrency: providerConcurrency,
            llmRetryLimit: providerRetryLimit,
            notionClient: notionClient,
            zoteroClient: zoteroClient,
            autoSyncNotion: notionAutoSync
        )
    }

    private func storedProviderAPIKey(for kind: ProviderKind) throws -> String? {
        if let direct = try keychain.get(kind.rawValue), !direct.isEmpty {
            return direct
        }
        if kind == .azureOpenAI,
           let legacyOpenAIKey = try keychain.get(ProviderKind.openAI.rawValue),
           !legacyOpenAIKey.isEmpty {
            return legacyOpenAIKey
        }
        return nil
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
