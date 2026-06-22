import Testing
import Foundation
@testable import ArxivResearchCore

@Suite("persistence and automation primitives")
struct PersistenceAndAutomationTests {
    @Test("SQLite store persists papers analyses query profiles and pending jobs")
    func persistsCoreObjects() throws {
        let store = try SQLiteResearchStore(path: temporaryDatabaseURL())
        let profile = QueryProfile(name: "Agents", rawQuery: "all:agent")
        let paper = Paper.fixture(arxivID: "2401.12345")
        let analysis = LLMAnalysis.fixture(tags: ["agents"])
        let job = SyncJob(kind: .syncNotion, payload: Data(paper.arxivID.utf8))

        try store.upsertQueryProfile(profile)
        try store.upsertPaper(paper)
        try store.saveAnalysis(analysis)
        try store.enqueue(job)

        #expect(try store.fetchQueryProfiles().map(\.rawQuery) == ["all:agent"])
        #expect(try store.fetchPapers().map(\.arxivID) == ["2401.12345"])
        #expect(try store.latestAnalysis(for: analysis.paperID)?.canonicalTags == ["agents"])
        #expect(try store.nextPendingJob()?.kind == .syncNotion)
    }

    @Test("SQLite store persists structured query settings")
    func persistsStructuredQuerySettings() throws {
        let store = try SQLiteResearchStore(path: temporaryDatabaseURL())
        let submittedAfter = ISO8601DateFormatter().date(from: "2026-06-01T00:00:00Z")!
        let rootGroup = StructuredQueryGroup(clauses: [
            StructuredQueryClause(node: .group(StructuredQueryGroup(clauses: [
                StructuredQueryClause(node: .term(StructuredQueryTerm(field: .all, value: "diffusion model", match: .phrase))),
                StructuredQueryClause(connector: .or, node: .term(StructuredQueryTerm(field: .all, value: "flow matching", match: .phrase)))
            ]))),
            StructuredQueryClause(connector: .andNot, node: .term(StructuredQueryTerm(field: .all, value: "robot", match: .phrase)))
        ])
        let profile = QueryProfile(
            name: "Generation",
            rawQuery: #"(all:"diffusion model" OR all:"flow matching") ANDNOT all:"robot""#,
            structuredQueryRoot: rootGroup,
            usesRawQuery: false,
            maxResults: 125,
            submittedAfter: submittedAfter
        )

        try store.upsertQueryProfile(profile)

        let fetched = try #require(store.fetchQueryProfiles().first)
        #expect(fetched.structuredQueryRoot == rootGroup)
        #expect(fetched.usesRawQuery == false)
        #expect(fetched.maxResults == 125)
        #expect(fetched.submittedAfter == submittedAfter)
        #expect(fetched.requestRawQuery == #"(all:"diffusion model" OR all:"flow matching") ANDNOT all:"robot" AND submittedDate:[202606010000 TO *]"#)
        #expect(QueryProfile.composeRequestRawQuery(rawQuery: "", submittedAfter: submittedAfter) == "submittedDate:[202606010000 TO *]")
    }

    @Test("legacy query profile JSON decodes with safe defaults")
    func decodesLegacyQueryProfileWithDefaults() throws {
        let data = """
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "name": "Legacy",
          "rawQuery": "all:agent",
          "refreshIntervalHours": 24,
          "isEnabled": true
        }
        """.data(using: .utf8)!

        let profile = try JSONDecoder().decode(QueryProfile.self, from: data)

        #expect(profile.rawQuery == "all:agent")
        #expect(profile.structuredQueryRoot != nil)
        #expect(profile.usesRawQuery == false)
        #expect(profile.maxResults == 50)
        #expect(profile.submittedAfter == nil)
        #expect(profile.requestRawQuery == "all:agent")
    }

    @Test("Legacy sync job JSON decodes with sync metadata defaults")
    func decodesLegacySyncJobWithMetadataDefaults() throws {
        let data = """
        {
          "id": "00000000-0000-0000-0000-000000000002",
          "kind": "summarizeAbstract",
          "state": "pending",
          "payload": "MjQwMS4xMjM0NQ==",
          "attempts": 0,
          "scheduledAt": "2026-06-22T00:00:00Z"
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let job = try decoder.decode(SyncJob.self, from: data)

        #expect(job.kind == .summarizeAbstract)
        #expect(String(data: job.payload, encoding: .utf8) == "2401.12345")
        #expect(job.idempotencyKey == nil)
        #expect(job.originDeviceID == nil)
        #expect(job.claimedByDeviceID == nil)
        #expect(job.claimedAt == nil)
        #expect(job.completedAt == nil)
    }

    @Test("Paper job helper stores typed paper payload and idempotency key")
    func paperJobHelperStoresTypedPayloadAndIdempotencyKey() throws {
        let job = try SyncJob.paperJob(kind: .summarizeAbstract, paperID: "2401.12345")

        #expect(job.kind == .summarizeAbstract)
        #expect(job.idempotencyKey == "summarizeAbstract:2401.12345")
        #expect(String(data: job.payload, encoding: .utf8) == "2401.12345")
        #expect(try job.typedPayload() == .paper(id: "2401.12345"))
    }

    @Test("Claiming a job records lease device metadata")
    func claimJobRecordsLeaseDeviceMetadata() throws {
        let store = try SQLiteResearchStore(path: temporaryDatabaseURL())
        let job = SyncJob(kind: .summarizeAbstract, payload: Data("2401.12345".utf8))
        try store.enqueue(job)

        let claimed = try #require(try store.claimJob(id: job.id, deviceID: "device-a"))

        #expect(claimed.state == .running)
        #expect(claimed.claimedByDeviceID == "device-a")
        #expect(claimed.claimedAt != nil)
        let persisted = try #require(try store.fetchJob(id: job.id))
        #expect(persisted.claimedByDeviceID == "device-a")
        #expect(abs(try #require(persisted.claimedAt).timeIntervalSince(try #require(claimed.claimedAt))) < 0.001)
    }

    @Test("Marking succeeded or failed jobs records completion time")
    func markJobTerminalStatesRecordCompletionTime() throws {
        let store = try SQLiteResearchStore(path: temporaryDatabaseURL())
        let succeeded = SyncJob(kind: .summarizeAbstract, payload: Data("2401.12345".utf8))
        let failed = SyncJob(kind: .syncNotion, payload: Data("2401.12345".utf8))
        try store.enqueue(succeeded)
        try store.enqueue(failed)

        try store.markJob(succeeded.id, state: .succeeded)
        try store.markJob(failed.id, state: .failed, error: "Boom")

        #expect(try store.fetchJob(id: succeeded.id)?.completedAt != nil)
        let failedJob = try #require(try store.fetchJob(id: failed.id))
        #expect(failedJob.completedAt != nil)
        #expect(failedJob.lastError == "Boom")
    }

    @Test("SQLite store recovers stale running jobs to pending")
    func recoversStaleRunningJobsToPending() throws {
        let store = try SQLiteResearchStore(path: temporaryDatabaseURL())
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var stale = try SyncJob.paperJob(kind: .summarizeAbstract, paperID: "2401.12345", state: .running)
        stale.claimedAt = now.addingTimeInterval(-3_601)
        stale.claimedByDeviceID = "old-helper"
        var active = try SyncJob.paperJob(kind: .deepRead, paperID: "2401.12345", state: .running)
        active.claimedAt = now.addingTimeInterval(-60)
        try store.enqueue(stale)
        try store.enqueue(active)

        let recovered = try store.recoverStaleRunningJobs(staleAfter: 3_600, now: now)

        #expect(recovered == 1)
        let recoveredJob = try #require(try store.fetchJob(id: stale.id))
        #expect(recoveredJob.state == .pending)
        #expect(recoveredJob.claimedAt == nil)
        #expect(recoveredJob.claimedByDeviceID == nil)
        #expect(recoveredJob.lastError?.contains("Recovered stale running job") == true)
        #expect(try store.fetchJob(id: active.id)?.state == .running)
    }

    @Test("SQLite store deduplicates active paper jobs by idempotency key")
    func deduplicatesActivePaperJobsByIdempotencyKey() throws {
        let store = try SQLiteResearchStore(path: temporaryDatabaseURL())
        let first = try SyncJob.paperJob(kind: .summarizeAbstract, paperID: "2401.12345")
        let duplicate = try SyncJob.paperJob(kind: .summarizeAbstract, paperID: "2401.12345")
        try store.enqueue(first)

        let storedDuplicate = try store.enqueueIfNeeded(duplicate)

        #expect(storedDuplicate.id == first.id)
        let jobs = try store.fetchJobs(kind: .summarizeAbstract, state: .pending, limit: 10)
        #expect(jobs.count == 1)
        #expect(jobs.first?.id == first.id)
    }

    @Test("SQLite store deletes paper with related analyses deep reads and paper jobs")
    func deletesPaperCascade() throws {
        let store = try SQLiteResearchStore(path: temporaryDatabaseURL())
        let paper = Paper.fixture(arxivID: "2401.12345")
        try store.upsertPaper(paper)
        try store.saveAnalysis(LLMAnalysis.fixture(tags: ["agents"]))
        try store.saveDeepRead(DeepReadReport(paperID: paper.arxivID, prompt: "Prompt", markdown: "Report", sourceKind: .html))
        try store.enqueue(SyncJob(kind: .deepRead, payload: Data(paper.arxivID.utf8)))

        try store.deletePaper(arxivID: paper.arxivID)

        #expect(try store.fetchPaper(arxivID: paper.arxivID) == nil)
        #expect(try store.latestDeepRead(for: paper.arxivID) == nil)
        #expect(try store.fetchJobs().isEmpty)
    }

    @Test("Deleting a query can optionally delete associated papers")
    func deletesQueryWithAssociatedPapersWhenRequested() throws {
        let store = try SQLiteResearchStore(path: temporaryDatabaseURL())
        let profile = QueryProfile(name: "Agents", rawQuery: "all:agent")
        let retainedProfile = QueryProfile(name: "Vision", rawQuery: "all:vision")
        let deletedPaper = Paper.fixture(arxivID: "2401.10000")
        var retainedPaper = Paper.fixture(arxivID: "2401.20000")
        retainedPaper.queryProfileIDs = [retainedProfile.id]
        var queryPaper = deletedPaper
        queryPaper.queryProfileIDs = [profile.id]

        try store.upsertQueryProfile(profile)
        try store.upsertQueryProfile(retainedProfile)
        try store.upsertPaper(queryPaper)
        try store.upsertPaper(retainedPaper)
        try store.deleteQueryProfile(id: profile.id, deleteAssociatedPapers: true)

        #expect(try store.fetchQueryProfiles().map(\.id).contains(profile.id) == false)
        #expect(try store.fetchPaper(arxivID: queryPaper.arxivID) == nil)
        #expect(try store.fetchPaper(arxivID: retainedPaper.arxivID) != nil)
    }

    @Test("Deleting a query keeps papers shared with other queries")
    func deletingQueryWithAssociatedPapersKeepsSharedPapers() throws {
        let store = try SQLiteResearchStore(path: temporaryDatabaseURL())
        let deletedProfile = QueryProfile(name: "Agents", rawQuery: "all:agent")
        let retainedProfile = QueryProfile(name: "Vision", rawQuery: "all:vision")
        var deletedOnlyPaper = Paper.fixture(arxivID: "2401.10000")
        deletedOnlyPaper.queryProfileIDs = [deletedProfile.id]
        var sharedPaper = Paper.fixture(arxivID: "2401.20000")
        sharedPaper.queryProfileIDs = [deletedProfile.id, retainedProfile.id]

        try store.upsertQueryProfile(deletedProfile)
        try store.upsertQueryProfile(retainedProfile)
        try store.upsertPaper(deletedOnlyPaper)
        try store.upsertPaper(sharedPaper)

        try store.deleteQueryProfile(id: deletedProfile.id, deleteAssociatedPapers: true)

        #expect(try store.fetchPaper(arxivID: deletedOnlyPaper.arxivID) == nil)
        let retainedSharedPaper = try #require(try store.fetchPaper(arxivID: sharedPaper.arxivID))
        #expect(retainedSharedPaper.queryProfileIDs == [retainedProfile.id])
    }

    @Test("Deleting only a query keeps associated papers")
    func deletesQueryWithoutAssociatedPapersWhenRequested() throws {
        let store = try SQLiteResearchStore(path: temporaryDatabaseURL())
        let profile = QueryProfile(name: "Agents", rawQuery: "all:agent")
        var paper = Paper.fixture(arxivID: "2401.10000")
        paper.queryProfileIDs = [profile.id]

        try store.upsertQueryProfile(profile)
        try store.upsertPaper(paper)
        try store.deleteQueryProfile(id: profile.id, deleteAssociatedPapers: false)

        #expect(try store.fetchQueryProfiles().isEmpty)
        let retainedPaper = try #require(try store.fetchPaper(arxivID: paper.arxivID))
        #expect(retainedPaper.queryProfileIDs.isEmpty)
    }

    @Test("App configuration store persists helper-readable non-secret settings")
    func persistsRuntimeSettings() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        let settings = RuntimeSettings(
            providerKind: .openAICompatible,
            providerModel: "model",
            providerDeploymentName: "deployment",
            providerBaseURL: "https://llm.example.com/v1",
            providerAPIVersion: "2024-10-21",
            providerMaxTokens: 4096,
            providerTemperature: 0.25,
            providerTopP: 0.9,
            providerConcurrency: 3,
            providerRetryLimit: 2,
            notionParentPageID: "page",
            notionDatabaseID: "db",
            notionDataSourceID: "ds",
            notionAutoSync: true,
            zoteroLibraryKind: "group",
            zoteroLibraryID: "123",
            zoteroCollectionKey: "COLL",
            academicProfileInput: "My papers and watched papers",
            generatedAcademicProfile: "I study agentic retrieval and evaluation.",
            summaryLanguage: .chinese,
            summaryPromptInstructions: "Prefer concise Chinese summaries.",
            deepReadPrompt: "Prompt"
        )

        try RuntimeSettingsStore(url: url).save(settings)

        #expect(try RuntimeSettingsStore(url: url).load() == settings)
    }

    @Test("Runtime settings decide summary queueing without reading secrets")
    func runtimeSettingsGateSummaryQueueingWithValidationFingerprint() throws {
        var settings = RuntimeSettings(
            providerKind: .openAICompatible,
            providerModel: "custom-model",
            providerBaseURL: "https://llm.example.com/v1"
        )

        #expect(settings.canQueueSummariesWithoutSecrets == false)

        settings.providerValidationFingerprint = RuntimeSettings.providerValidationFingerprint(
            kind: .openAICompatible,
            model: "custom-model",
            deploymentName: "",
            baseURL: "https://llm.example.com/v1",
            apiVersion: "2024-10-21"
        )
        #expect(settings.canQueueSummariesWithoutSecrets == true)

        settings.providerModel = "changed-model"
        #expect(settings.canQueueSummariesWithoutSecrets == false)
    }

    @Test("LLM analysis parser accepts minimal personalized summary JSON")
    func parsesMinimalSummaryJSON() throws {
        let analysis = LLMAnalysisParser.parse(
            """
            {"one_sentence_summary":"Short.","rationale":"Useful for my profile.","relevance_score":87,"canonical_tags":["agent-evaluation"]}
            """,
            paperID: "2606.00001"
        )

        #expect(analysis.paperID == "2606.00001")
        #expect(analysis.oneSentenceSummary == "Short.")
        #expect(analysis.rationale == "Useful for my profile.")
        #expect(analysis.relevanceScore == 87)
        #expect(analysis.canonicalTags == ["agent-evaluation"])
        #expect(analysis.keyContributions.isEmpty)
        #expect(analysis.methods.isEmpty)
        #expect(analysis.results.isEmpty)
        #expect(analysis.limitations.isEmpty)
    }

    @Test("Paper JSON without local added date remains decodable")
    func decodesLegacyPaperWithoutAddedAt() throws {
        let data = """
        {
          "arxivID": "2401.11111",
          "title": "Legacy Paper",
          "abstract": "Old local JSON.",
          "authors": ["Ada"],
          "categories": [],
          "queryProfileIDs": [],
          "status": "new",
          "tags": []
        }
        """.data(using: .utf8)!

        let paper = try JSONDecoder().decode(Paper.self, from: data)

        #expect(paper.arxivID == "2401.11111")
        #expect(paper.addedAt == nil)
    }

    @Test("SQLite store deletes jobs by kind and state")
    func deletesJobsByKindAndState() throws {
        let store = try SQLiteResearchStore(path: temporaryDatabaseURL())
        let paper = Paper.fixture(arxivID: "2401.12345")
        try store.upsertPaper(paper)
        try store.enqueue(SyncJob(kind: .summarizeAbstract, payload: Data(paper.arxivID.utf8)))
        try store.enqueue(SyncJob(kind: .syncNotion, payload: Data(paper.arxivID.utf8)))
        var failedJob = SyncJob(kind: .syncNotion, state: .failed, payload: Data(paper.arxivID.utf8))
        failedJob.lastError = "Boom"
        try store.enqueue(failedJob)

        try store.deleteJobs(kind: .syncNotion, state: .pending)

        let remaining = try store.fetchJobs(limit: 10)
        #expect(remaining.map(\.kind).filter { $0 == .syncNotion }.count == 1)
        #expect(remaining.first { $0.kind == .syncNotion }?.state == .failed)
        #expect(remaining.contains { $0.kind == .summarizeAbstract })
    }

    @Test("Automation jobs process configured LLM work even when earlier sync jobs are unconfigured")
    @MainActor
    func pendingJobsDoNotStarveConfiguredLLMWork() async throws {
        let store = try SQLiteResearchStore(path: temporaryDatabaseURL())
        let paper = Paper.fixture(arxivID: "2401.12345")
        try store.upsertPaper(paper)
        try store.enqueue(SyncJob(kind: .syncZotero, payload: Data(paper.arxivID.utf8)))
        try store.enqueue(SyncJob(kind: .summarizeAbstract, payload: Data(paper.arxivID.utf8)))
        let processor = AutomationJobProcessor(
            store: store,
            configuration: AutomationConfiguration(
                llmProvider: StubLLMProvider(),
                llmAPIKey: "test-key"
            )
        )

        let result = try await processor.runPendingJobs(limit: 10)

        #expect(result.succeeded == 1)
        #expect(result.skipped == 1)
        #expect(try store.latestAnalysis(for: paper.arxivID)?.oneSentenceSummary == "Useful paper.")
    }

    @Test("Automation can run one selected pending job")
    @MainActor
    func runsSingleSelectedJob() async throws {
        let store = try SQLiteResearchStore(path: temporaryDatabaseURL())
        let paper = Paper.fixture(arxivID: "2401.12345")
        try store.upsertPaper(paper)
        let skipped = SyncJob(kind: .summarizeAbstract, payload: Data(paper.arxivID.utf8))
        let selected = SyncJob(kind: .summarizeAbstract, payload: Data(paper.arxivID.utf8))
        try store.enqueue(skipped)
        try store.enqueue(selected)
        let processor = AutomationJobProcessor(
            store: store,
            configuration: AutomationConfiguration(
                llmProvider: StubLLMProvider(),
                llmAPIKey: "test-key"
            )
        )

        let result = try await processor.runJob(id: selected.id)

        #expect(result.succeeded == 1)
        #expect(try store.fetchJob(id: selected.id)?.state == .succeeded)
        #expect(try store.fetchJob(id: skipped.id)?.state == .pending)
    }

    @Test("Automation can manually restart one running job")
    @MainActor
    func restartsSelectedRunningJob() async throws {
        let store = try SQLiteResearchStore(path: temporaryDatabaseURL())
        let paper = Paper.fixture(arxivID: "2401.12345")
        try store.upsertPaper(paper)
        let job = try SyncJob.paperJob(kind: .summarizeAbstract, paperID: paper.arxivID)
        try store.enqueue(job)
        _ = try #require(try store.claimJob(id: job.id))
        let processor = AutomationJobProcessor(
            store: store,
            configuration: AutomationConfiguration(
                llmProvider: StubLLMProvider(),
                llmAPIKey: "test-key"
            )
        )

        let result = try await processor.runJob(id: job.id)

        #expect(result.succeeded == 1)
        #expect(try store.fetchJob(id: job.id)?.state == .succeeded)
        #expect(try store.latestAnalysis(for: paper.arxivID)?.oneSentenceSummary == "Useful paper.")
    }

    @Test("Automation retries transient LLM failures")
    @MainActor
    func retriesTransientLLMFailures() async throws {
        let store = try SQLiteResearchStore(path: temporaryDatabaseURL())
        let paper = Paper.fixture(arxivID: "2401.12345")
        try store.upsertPaper(paper)
        try store.enqueue(SyncJob(kind: .summarizeAbstract, payload: Data(paper.arxivID.utf8)))
        let provider = RetryingStubLLMProvider()
        let processor = AutomationJobProcessor(
            store: store,
            configuration: AutomationConfiguration(
                llmProvider: provider,
                llmAPIKey: "test-key",
                llmRetryLimit: 1
            )
        )

        let result = try await processor.runPendingJobs(limit: 10)

        #expect(result.succeeded == 1)
        #expect(provider.attempts == 2)
        #expect(try store.latestAnalysis(for: paper.arxivID)?.oneSentenceSummary == "Useful paper.")
    }

    @Test("Automation queues Notion sync after LLM analysis when auto sync is enabled")
    @MainActor
    func queuesNotionSyncAfterAnalysisWhenEnabled() async throws {
        let store = try SQLiteResearchStore(path: temporaryDatabaseURL())
        let paper = Paper.fixture(arxivID: "2401.12345")
        try store.upsertPaper(paper)
        try store.enqueue(SyncJob(kind: .summarizeAbstract, payload: Data(paper.arxivID.utf8)))
        let processor = AutomationJobProcessor(
            store: store,
            configuration: AutomationConfiguration(
                llmProvider: StubLLMProvider(),
                llmAPIKey: "test-key",
                notionClient: StubNotionSyncClient(),
                autoSyncNotion: true
            )
        )

        let result = try await processor.runPendingJobs(limit: 10)

        #expect(result.succeeded == 1)
        let pendingKinds = try store.fetchJobs(state: .pending).map(\.kind)
        #expect(pendingKinds == [.syncNotion])
    }

    @Test("Automation fetch can avoid queuing summaries when LLM is unconfigured")
    func automationFetchSkipsSummaryQueueWithoutLLM() async throws {
        let store = try SQLiteResearchStore(path: temporaryDatabaseURL())
        let profile = QueryProfile(name: "Agents", rawQuery: "all:agent")
        try store.upsertQueryProfile(profile)
        let service = ResearchAutomationService(
            store: store,
            arxivClient: StubArxivClient(),
            queueSummaries: false
        )

        try await service.runOnce()

        #expect(try store.fetchPapers().map(\.arxivID) == ["2401.54321"])
        #expect(try store.fetchJobs().isEmpty)
    }

    @Test("Automation fetch queues at most one summary job per paper")
    func automationFetchDeduplicatesSummaryQueue() async throws {
        let store = try SQLiteResearchStore(path: temporaryDatabaseURL())
        let profile = QueryProfile(name: "Agents", rawQuery: "all:agent")
        try store.upsertQueryProfile(profile)
        let service = ResearchAutomationService(
            store: store,
            arxivClient: StubArxivClient(),
            queueSummaries: true
        )

        try await service.runOnce(now: Date(timeIntervalSince1970: 1_800_000_000))
        try await service.runOnce(now: Date(timeIntervalSince1970: 1_800_090_000))

        let jobs = try store.fetchJobs(kind: .summarizeAbstract, state: .pending, limit: 10)
        #expect(jobs.count == 1)
        #expect(jobs.first?.idempotencyKey == "summarizeAbstract:2401.54321")
    }

    @Test("Automation fetch uses query profile max results and submitted-after filter")
    func automationFetchUsesQueryProfileRequestSettings() async throws {
        let store = try SQLiteResearchStore(path: temporaryDatabaseURL())
        let client = RecordingArxivClient()
        let submittedAfter = ISO8601DateFormatter().date(from: "2026-06-01T00:00:00Z")!
        let profile = QueryProfile(
            name: "Agents",
            rawQuery: "all:agent",
            maxResults: 123,
            submittedAfter: submittedAfter
        )
        try store.upsertQueryProfile(profile)
        let service = ResearchAutomationService(
            store: store,
            arxivClient: client,
            queueSummaries: false
        )

        try await service.runOnce()

        let request = try #require(client.requests.first)
        #expect(request.maxResults == 123)
        #expect(try request.url().absoluteString.contains("max_results=123"))
        #expect(try request.url().absoluteString.contains("submittedDate:%5B202606010000+TO+%2A%5D"))
    }

    @Test("Automation fetch preserves existing local added date")
    func automationFetchPreservesExistingAddedAt() async throws {
        let store = try SQLiteResearchStore(path: temporaryDatabaseURL())
        let profile = QueryProfile(name: "Agents", rawQuery: "all:agent")
        let oldProfileID = UUID()
        let originalAddedAt = Date(timeIntervalSince1970: 1_704_067_200)
        var existing = Paper.fixture(arxivID: "2401.54321")
        existing.addedAt = originalAddedAt
        existing.queryProfileIDs = [oldProfileID]
        try store.upsertQueryProfile(profile)
        try store.upsertPaper(existing)
        let service = ResearchAutomationService(
            store: store,
            arxivClient: StubArxivClient(),
            queueSummaries: false
        )

        try await service.runOnce(now: Date(timeIntervalSince1970: 1_781_139_600))

        let fetched = try store.fetchPaper(arxivID: "2401.54321")
        let paper = try #require(fetched)
        #expect(paper.addedAt == originalAddedAt)
        #expect(Set(paper.queryProfileIDs) == Set([oldProfileID, profile.id]))
    }

    @Test("Automation fetch backfills missing local added date from fetch time")
    func automationFetchBackfillsMissingAddedAtFromFetchTime() async throws {
        let store = try SQLiteResearchStore(path: temporaryDatabaseURL())
        let profile = QueryProfile(name: "Agents", rawQuery: "all:agent")
        let publishedAt = Date(timeIntervalSince1970: 1_704_067_200)
        let updatedAt = Date(timeIntervalSince1970: 1_781_139_600)
        let fetchTime = Date(timeIntervalSince1970: 1_800_000_000)
        var existing = Paper.fixture(arxivID: "2401.54321")
        existing.addedAt = nil
        existing.publishedAt = publishedAt
        existing.updatedAt = updatedAt
        try store.upsertQueryProfile(profile)
        try store.upsertPaper(existing)
        let service = ResearchAutomationService(
            store: store,
            arxivClient: StubArxivClient(),
            queueSummaries: false
        )

        try await service.runOnce(now: fetchTime)

        let fetched = try store.fetchPaper(arxivID: "2401.54321")
        let paper = try #require(fetched)
        #expect(paper.addedAt == fetchTime)
    }

    @Test("Tag canonicalizer lowercases trims and records aliases")
    func canonicalizesTags() throws {
        let canonicalizer = SimpleTagCanonicalizer()

        let tags = canonicalizer.canonicalize(
            suggestedTags: [" LLMs ", "llm", "Retrieval-Augmented Generation"],
            existing: []
        )

        #expect(tags.map(\.name).sorted() == ["llm", "retrieval-augmented generation"])
        #expect(tags.first { $0.name == "llm" }?.aliases.contains(" LLMs ") == true)
    }

    @Test("Notion page request writes paper and analysis properties")
    func buildsNotionPageRequest() throws {
        let config = NotionConfig(tokenRef: "notion", parentPageID: "page-123", databaseID: "db-123", dataSourceID: "ds-123")
        let request = try NotionAPIClient(config: config).buildUpsertPageRequest(
            paper: .fixture(arxivID: "2401.99999"),
            analysis: .fixture(tags: ["llm"]),
            deepRead: nil
        )

        let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
        #expect(request.url?.absoluteString == "https://api.notion.com/v1/pages")
        #expect(body.contains("data_source_id"))
        #expect(body.contains("2401.99999"))
        #expect(body.contains("llm"))
    }

    @Test("Zotero PDF attachment request creates child attachment")
    func buildsZoteroPDFAttachmentRequest() throws {
        let config = ZoteroConfig(tokenRef: "zotero", library: .group(id: 456), collectionKey: "COLL456")
        let paper = Paper.fixture(arxivID: "2402.00001")

        let request = try ZoteroAPIClient(config: config).buildCreatePDFAttachmentRequest(parentItemKey: "ITEM123", paper: paper)

        let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
        #expect(request.url?.absoluteString == "https://api.zotero.org/groups/456/items")
        #expect(body.contains("\"itemType\":\"attachment\""))
        #expect(body.contains("\"parentItem\":\"ITEM123\""))
        #expect(body.contains("application/pdf"))
    }
}

private struct StubLLMProvider: LLMProvider {
    var config = ProviderConfig(
        kind: .openAI,
        model: "stub",
        baseURL: URL(string: "https://example.com")!,
        apiKeyRef: "stub"
    )

    func buildRequest(apiKey: String, payload: LLMPromptPayload) throws -> URLRequest {
        URLRequest(url: URL(string: "https://example.com")!)
    }

    func complete(apiKey: String, payload: LLMPromptPayload) async throws -> String {
        """
        {
          "one_sentence_summary": "Useful paper.",
          "key_contributions": [],
          "methods": [],
          "results": [],
          "limitations": [],
          "relevance_score": 0.7,
          "canonical_tags": ["agents"],
          "rationale": "Stubbed."
        }
        """
    }
}

private final class RetryingStubLLMProvider: LLMProvider, @unchecked Sendable {
    var config = ProviderConfig(
        kind: .openAI,
        model: "stub",
        baseURL: URL(string: "https://example.com")!,
        apiKeyRef: "stub"
    )
    var attempts = 0

    func buildRequest(apiKey: String, payload: LLMPromptPayload) throws -> URLRequest {
        URLRequest(url: URL(string: "https://example.com")!)
    }

    func complete(apiKey: String, payload: LLMPromptPayload) async throws -> String {
        attempts += 1
        if attempts == 1 {
            throw LLMProviderError.requestFailed(429, "rate limited")
        }
        return """
        {
          "one_sentence_summary": "Useful paper.",
          "key_contributions": [],
          "methods": [],
          "results": [],
          "limitations": [],
          "relevance_score": 0.7,
          "canonical_tags": ["agents"],
          "rationale": "Stubbed."
        }
        """
    }
}

private struct StubNotionSyncClient: NotionSyncClient {
    func buildCreateDatabaseRequest() throws -> URLRequest {
        URLRequest(url: URL(string: "https://notion.example.com")!)
    }

    func buildCreatePageRequest(paper: Paper, analysis: LLMAnalysis?, deepRead: DeepReadReport?) throws -> URLRequest {
        URLRequest(url: URL(string: "https://notion.example.com/pages")!)
    }

    func buildUpsertPageRequest(paper: Paper, analysis: LLMAnalysis?, deepRead: DeepReadReport?) throws -> URLRequest {
        URLRequest(url: URL(string: "https://notion.example.com/pages")!)
    }

    func buildUpdatePageRequest(pageID: String, paper: Paper, analysis: LLMAnalysis?, deepRead: DeepReadReport?) throws -> URLRequest {
        URLRequest(url: URL(string: "https://notion.example.com/pages/\(pageID)")!)
    }

    func buildAppendPageContentRequest(pageID: String, paper: Paper, analysis: LLMAnalysis?, deepRead: DeepReadReport?) throws -> URLRequest {
        URLRequest(url: URL(string: "https://notion.example.com/blocks/\(pageID)/children")!)
    }
}

private struct StubArxivClient: ArxivClient {
    func search(_ request: ArxivAPIRequest) async throws -> ArxivFeed {
        ArxivFeed(
            totalResults: 1,
            itemsPerPage: 1,
            entries: [
                ArxivEntry(
                    arxivID: "2401.54321",
                    versionedID: "2401.54321v1",
                    title: "Stub Paper",
                    summary: "Stub abstract.",
                    authors: ["Ada"],
                    categories: []
                )
            ]
        )
    }
}

private final class RecordingArxivClient: ArxivClient {
    private(set) var requests: [ArxivAPIRequest] = []

    func search(_ request: ArxivAPIRequest) async throws -> ArxivFeed {
        requests.append(request)
        return ArxivFeed(
            totalResults: 1,
            itemsPerPage: 1,
            entries: [
                ArxivEntry(
                    arxivID: "2401.54321",
                    versionedID: "2401.54321v1",
                    title: "Stub Paper",
                    summary: "Stub abstract.",
                    authors: ["Ada"],
                    categories: []
                )
            ]
        )
    }
}

private func temporaryDatabaseURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("sqlite")
}
