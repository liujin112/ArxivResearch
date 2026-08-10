import Foundation

public struct AutomationConfiguration {
    public var llmProvider: (any LLMProvider)?
    public var llmAPIKey: String?
    public var summaryPromptOptions: SummaryPromptOptions
    public var deepReadPrompt: String
    public var llmMaxTokens: Int
    public var llmTemperature: Double
    public var llmTopP: Double?
    public var llmConcurrency: Int
    public var llmRetryLimit: Int
    public var notionClient: (any NotionSyncClient)?
    public var zoteroClient: (any ZoteroSyncClient)?
    public var autoSyncNotion: Bool
    public var activeAnalyzeUnanalyzedPapers: Bool

    public init(
        llmProvider: (any LLMProvider)? = nil,
        llmAPIKey: String? = nil,
        summaryPromptOptions: SummaryPromptOptions = SummaryPromptOptions(),
        deepReadPrompt: String = DefaultPrompts.deepRead,
        llmMaxTokens: Int = 4096,
        llmTemperature: Double = 0.2,
        llmTopP: Double? = nil,
        llmConcurrency: Int = 2,
        llmRetryLimit: Int = 1,
        notionClient: (any NotionSyncClient)? = nil,
        zoteroClient: (any ZoteroSyncClient)? = nil,
        autoSyncNotion: Bool = false,
        activeAnalyzeUnanalyzedPapers: Bool = true
    ) {
        self.llmProvider = llmProvider
        self.llmAPIKey = llmAPIKey
        self.summaryPromptOptions = summaryPromptOptions
        self.deepReadPrompt = deepReadPrompt
        self.llmMaxTokens = max(1, llmMaxTokens)
        self.llmTemperature = llmTemperature
        self.llmTopP = llmTopP
        self.llmConcurrency = max(1, llmConcurrency)
        self.llmRetryLimit = max(0, llmRetryLimit)
        self.notionClient = notionClient
        self.zoteroClient = zoteroClient
        self.autoSyncNotion = autoSyncNotion
        self.activeAnalyzeUnanalyzedPapers = activeAnalyzeUnanalyzedPapers
    }

    public func canProcess(_ kind: SyncJob.Kind) -> Bool {
        switch kind {
        case .summarizeAbstract, .deepRead:
            llmProvider != nil && llmAPIKey?.isEmpty == false
        case .syncNotion:
            notionClient != nil
        case .syncZotero:
            zoteroClient != nil
        case .fetchArxiv:
            true
        }
    }
}

public struct AutomationJobRunResult: Codable, Hashable, Sendable {
    public var succeeded: Int
    public var failed: Int
    public var skipped: Int

    public init(succeeded: Int = 0, failed: Int = 0, skipped: Int = 0) {
        self.succeeded = succeeded
        self.failed = failed
        self.skipped = skipped
    }
}

public enum DefaultPrompts {
    public static let summaryInstructions = """
    Keep the one-sentence summary concise. Explain why the paper is worth attention for the configured research profile. Tags must stay concise and reusable.
    """

    public static let summaryLockedProtocol = """
    You analyze arXiv papers for a personalized research workflow. Return compact JSON only with exactly these required keys: one_sentence_summary, rationale, relevance_score, canonical_tags.
    relevance_score must be an integer from 0 to 100.
    canonical_tags must be stable English kebab-case nouns or noun phrases.
    rationale is a short why-it-matters explanation for the user's research profile, not hidden chain-of-thought.
    Score high for direct topic overlap, similar tasks or datasets, transferable methods, or strong methodological inspiration even when the application domain differs. Score low for generic popularity alone.
    """

    public static let deepRead = """
    You are a careful research assistant. Produce a Markdown deep-read report with:
    1. Problem and motivation
    2. Core method
    3. Key equations or algorithms
    4. Evidence and results
    5. Limitations
    6. Follow-up questions
    Keep claims tied to the supplied paper text.
    """
}

@MainActor
public final class AutomationJobProcessor {
    private let store: SQLiteResearchStore
    private let configuration: AutomationConfiguration
    private let contentExtractor: any ContentExtractor
    private let arxivClient: any ArxivClient
    private let session: URLSession
    private let onJobStateChange: (() throws -> Void)?
    private static let staleRunningJobTimeout: TimeInterval = 30 * 60

    public init(
        store: SQLiteResearchStore,
        configuration: AutomationConfiguration,
        contentExtractor: any ContentExtractor = URLContentExtractor(),
        arxivClient: any ArxivClient = ArxivHTTPClient(),
        session: URLSession = .shared,
        onJobStateChange: (() throws -> Void)? = nil
    ) {
        self.store = store
        self.configuration = configuration
        self.contentExtractor = contentExtractor
        self.arxivClient = arxivClient
        self.session = session
        self.onJobStateChange = onJobStateChange
    }

    public func runPendingJobs(limit: Int = 20, kind: SyncJob.Kind? = nil) async throws -> AutomationJobRunResult {
        var result = AutomationJobRunResult()
        let recovered = try store.recoverStaleRunningJobs(kind: kind, staleAfter: Self.staleRunningJobTimeout)
        if recovered > 0 {
            try onJobStateChange?()
        }
        let maxJobs = max(1, limit)
        var completedJobs = 0
        var skippedJobIDs = Set<SyncJob.ID>()

        while completedJobs < maxJobs {
            let jobs = try store.fetchPendingJobs(kind: kind, scheduledThrough: Date(), limit: maxJobs)
            guard !jobs.isEmpty else {
                break
            }

            var madeProgress = false
            for job in jobs {
                guard completedJobs < maxJobs else {
                    break
                }
                guard canProcess(job) else {
                    if skippedJobIDs.insert(job.id).inserted {
                        result.skipped += 1
                    }
                    continue
                }

                let jobResult = try await runClaimedJob(id: job.id, allowedStates: [.pending])
                result.succeeded += jobResult.succeeded
                result.failed += jobResult.failed
                if jobResult.skipped > 0, skippedJobIDs.insert(job.id).inserted {
                    result.skipped += jobResult.skipped
                }

                let finishedJobs = jobResult.succeeded + jobResult.failed
                if finishedJobs > 0 {
                    completedJobs += finishedJobs
                    madeProgress = true
                }
            }

            if !madeProgress {
                break
            }
        }
        return result
    }

    public func runJob(id: UUID, allowRetryFailed: Bool = true) async throws -> AutomationJobRunResult {
        let allowedStates: Set<SyncJob.State> = allowRetryFailed ? [.pending, .failed] : [.pending]
        return try await runClaimedJob(id: id, allowedStates: allowedStates)
    }

    private func canProcess(_ job: SyncJob) -> Bool {
        configuration.canProcess(job.kind)
    }

    private func runClaimedJob(id: UUID, allowedStates: Set<SyncJob.State>) async throws -> AutomationJobRunResult {
        guard let existing = try store.fetchJob(id: id) else {
            return AutomationJobRunResult(skipped: 1)
        }
        guard canProcess(existing) else {
            return AutomationJobRunResult(skipped: 1)
        }
        guard let job = try store.claimJob(id: id, allowedStates: allowedStates) else {
            return AutomationJobRunResult(skipped: 1)
        }
        try onJobStateChange?()
        do {
            try await process(job)
            try store.markJob(job.id, state: .succeeded)
            try onJobStateChange?()
            return AutomationJobRunResult(succeeded: 1)
        } catch {
            try store.markJob(job.id, state: .failed, error: error.localizedDescription)
            try onJobStateChange?()
            return AutomationJobRunResult(failed: 1)
        }
    }

    private func process(_ job: SyncJob) async throws {
        switch job.kind {
        case .summarizeAbstract:
            try await summarize(job)
        case .deepRead:
            try await deepRead(job)
        case .syncNotion:
            try await syncNotion(job)
        case .syncZotero:
            try await syncZotero(job)
        case .fetchArxiv:
            guard case let .queryProfile(profileID) = try job.typedPayload() else {
                throw AutomationError.invalidQueryJobPayload
            }
            let service = ResearchAutomationService(
                store: store,
                arxivClient: arxivClient,
                queueSummaries: configuration.canProcess(.summarizeAbstract)
                    && configuration.activeAnalyzeUnanalyzedPapers,
                interProfileDelay: .zero
            )
            guard try await service.runProfile(profileID: profileID) else {
                throw AutomationError.queryFetchAlreadyRunning
            }
        }
    }

    private func summarize(_ job: SyncJob) async throws {
        let paper = try paper(from: job)
        guard let provider = configuration.llmProvider, let apiKey = configuration.llmAPIKey else {
            throw AutomationError.missingLLMConfiguration
        }
        let content = try await completeLLM(
            provider: provider,
            apiKey: apiKey,
            payload: .summaryPrompt(title: paper.title, abstract: paper.abstract, options: configuration.summaryPromptOptions)
        )
        let analysis = LLMAnalysisParser.parse(content, paperID: paper.arxivID)
        try store.saveAnalysis(analysis)
        var updatedPaper = paper
        updatedPaper.status = .summarized
        updatedPaper.tags = analysis.canonicalTags
        try store.upsertPaper(updatedPaper)
        try enqueueNotionSyncIfEnabled(for: updatedPaper)
    }

    private func deepRead(_ job: SyncJob) async throws {
        let paper = try paper(from: job)
        guard let provider = configuration.llmProvider, let apiKey = configuration.llmAPIKey else {
            throw AutomationError.missingLLMConfiguration
        }
        let extracted = try await contentExtractor.markdown(for: paper)
        let chunks = Chunker().chunks(markdown: extracted.markdown)
        let sections = try await completeDeepReadChunks(provider: provider, apiKey: apiKey, paper: paper, chunks: chunks)
        let report = DeepReadReport(
            paperID: paper.arxivID,
            prompt: configuration.deepReadPrompt,
            markdown: sections.joined(separator: "\n\n---\n\n"),
            sourceKind: extracted.sourceKind
        )
        try store.saveDeepRead(report)
        var updatedPaper = paper
        updatedPaper.status = .deepRead
        try store.upsertPaper(updatedPaper)
        try enqueueNotionSyncIfEnabled(for: updatedPaper)
    }

    private func syncNotion(_ job: SyncJob) async throws {
        var paper = try paper(from: job)
        guard let notionClient = configuration.notionClient else {
            throw AutomationError.missingNotionConfiguration
        }
        let analysis = try store.latestAnalysis(for: paper.arxivID)
        let deepRead = try store.latestDeepRead(for: paper.arxivID)
        if let pageID = paper.notionPageID, !pageID.isEmpty {
            _ = try await sendNotion(notionClient) {
                try notionClient.buildUpdatePageRequest(pageID: pageID, paper: paper, analysis: analysis, deepRead: deepRead)
            }
            _ = try await sendNotion(notionClient) {
                try notionClient.buildAppendPageContentRequest(pageID: pageID, paper: paper, analysis: analysis, deepRead: deepRead)
            }
        } else {
            let data = try await sendNotion(notionClient) {
                try notionClient.buildCreatePageRequest(paper: paper, analysis: analysis, deepRead: deepRead)
            }
            if let pageID = NotionResponseParser.createdPageID(from: data) {
                paper.notionPageID = pageID
                try store.upsertPaper(paper)
            }
        }
    }

    private func syncZotero(_ job: SyncJob) async throws {
        let paper = try paper(from: job)
        guard let zoteroClient = configuration.zoteroClient else {
            throw AutomationError.missingZoteroConfiguration
        }
        let analysis = try store.latestAnalysis(for: paper.arxivID)
        let data = try await send(zoteroClient.buildCreateItemRequest(paper: paper, analysis: analysis))
        if let itemKey = ZoteroResponseParser.createdItemKey(from: data) {
            _ = try await send(zoteroClient.buildCreateNoteRequest(
                parentItemKey: itemKey,
                paper: paper,
                analysis: analysis,
                deepRead: try store.latestDeepRead(for: paper.arxivID)
            ))
            _ = try await send(zoteroClient.buildCreatePDFAttachmentRequest(parentItemKey: itemKey, paper: paper))
        }
    }

    private func paper(from job: SyncJob) throws -> Paper {
        guard let paperID = String(data: job.payload, encoding: .utf8), !paperID.isEmpty else {
            throw AutomationError.invalidJobPayload
        }
        guard let paper = try store.fetchPaper(arxivID: paperID) else {
            throw AutomationError.paperNotFound(paperID)
        }
        return paper
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AutomationError.invalidHTTPResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw AutomationError.httpFailure(httpResponse.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }

    private func sendNotion(
        _ client: any NotionSyncClient,
        request buildRequest: () throws -> URLRequest
    ) async throws -> Data {
        do {
            return try await send(buildRequest())
        } catch let error as AutomationError {
            guard case let .httpFailure(status, body) = error,
                  status == 400,
                  NotionResponseParser.missingPropertyName(from: body) != nil
            else {
                throw error
            }
            _ = try await send(client.buildEnsurePaperPropertiesRequest())
            return try await send(buildRequest())
        }
    }

    private func completeLLM(provider: any LLMProvider, apiKey: String, payload: LLMPromptPayload) async throws -> String {
        let configuredPayload = payload.applying(
            maxTokens: configuration.llmMaxTokens,
            temperature: configuration.llmTemperature,
            topP: configuration.llmTopP
        )
        return try await Self.completeLLM(
            provider: provider,
            apiKey: apiKey,
            payload: configuredPayload,
            retryLimit: configuration.llmRetryLimit
        )
    }

    private func completeDeepReadChunks(provider: any LLMProvider, apiKey: String, paper: Paper, chunks: [String]) async throws -> [String] {
        let concurrency = max(1, min(configuration.llmConcurrency, chunks.count))
        var nextIndex = 0
        var sections = Array(repeating: "", count: chunks.count)
        let prompt = configuration.deepReadPrompt
        let maxTokens = configuration.llmMaxTokens
        let temperature = configuration.llmTemperature
        let topP = configuration.llmTopP
        let retryLimit = configuration.llmRetryLimit

        try await withThrowingTaskGroup(of: (Int, String).self) { group in
            func addNext() {
                guard nextIndex < chunks.count else { return }
                let index = nextIndex
                let chunk = chunks[index]
                nextIndex += 1
                group.addTask {
                    let payload = LLMPromptPayload
                        .deepReadPrompt(
                            title: "\(paper.title) (chunk \(index + 1)/\(chunks.count))",
                            markdown: chunk,
                            customPrompt: prompt
                        )
                        .applying(maxTokens: maxTokens, temperature: temperature, topP: topP)
                    return (
                        index,
                        try await Self.completeLLM(
                            provider: provider,
                            apiKey: apiKey,
                            payload: payload,
                            retryLimit: retryLimit
                        )
                    )
                }
            }

            for _ in 0..<concurrency {
                addNext()
            }
            while let (index, content) = try await group.next() {
                sections[index] = content
                addNext()
            }
        }
        return sections
    }

    private static func completeLLM(provider: any LLMProvider, apiKey: String, payload: LLMPromptPayload, retryLimit: Int) async throws -> String {
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
        throw lastError ?? AutomationError.missingLLMConfiguration
    }

    private func enqueueNotionSyncIfEnabled(for paper: Paper) throws {
        guard configuration.autoSyncNotion, configuration.canProcess(.syncNotion) else {
            return
        }
        let payload = Data(paper.arxivID.utf8)
        let existing = try store.fetchJobs(kind: .syncNotion, state: .pending, limit: 500)
        guard !existing.contains(where: { $0.payload == payload }) else {
            return
        }
        try store.enqueueIfNeeded(try SyncJob.paperJob(kind: .syncNotion, paperID: paper.arxivID))
        try onJobStateChange?()
    }
}

public enum AutomationError: Error, LocalizedError {
    case missingLLMConfiguration
    case missingNotionConfiguration
    case missingZoteroConfiguration
    case invalidJobPayload
    case invalidQueryJobPayload
    case queryFetchAlreadyRunning
    case paperNotFound(String)
    case invalidHTTPResponse
    case httpFailure(Int, String)

    public var errorDescription: String? {
        switch self {
        case .missingLLMConfiguration:
            "LLM provider and API key are required for this job."
        case .missingNotionConfiguration:
            "Notion client configuration is required for this job."
        case .missingZoteroConfiguration:
            "Zotero client configuration is required for this job."
        case .invalidJobPayload:
            "The job payload does not contain a paper ID."
        case .invalidQueryJobPayload:
            "The fetch job payload does not contain a subscription ID."
        case .queryFetchAlreadyRunning:
            "This subscription is already being fetched by another process."
        case let .paperNotFound(id):
            "Paper \(id) was not found in the local database."
        case .invalidHTTPResponse:
            "The sync endpoint returned a non-HTTP response."
        case let .httpFailure(status, body):
            "Sync endpoint failed with HTTP \(status): \(body)"
        }
    }
}

public enum LLMAnalysisParser {
    public static func parse(_ content: String, paperID: String) -> LLMAnalysis {
        guard let data = content.data(using: .utf8),
              let dto = try? JSONDecoder().decode(SummaryDTO.self, from: data)
        else {
            return LLMAnalysis(
                paperID: paperID,
                oneSentenceSummary: content.prefix(500).description,
                rationale: content
            )
        }
        return LLMAnalysis(
            paperID: paperID,
            oneSentenceSummary: dto.oneSentenceSummary,
            keyContributions: dto.keyContributions ?? [],
            methods: dto.methods ?? [],
            results: dto.results ?? [],
            limitations: dto.limitations ?? [],
            relevanceScore: dto.relevanceScore,
            canonicalTags: dto.canonicalTags,
            rationale: dto.rationale
        )
    }

    private struct SummaryDTO: Decodable {
        var oneSentenceSummary: String
        var keyContributions: [String]?
        var methods: [String]?
        var results: [String]?
        var limitations: [String]?
        var relevanceScore: Double
        var canonicalTags: [String]
        var rationale: String

        enum CodingKeys: String, CodingKey {
            case oneSentenceSummary = "one_sentence_summary"
            case keyContributions = "key_contributions"
            case methods
            case results
            case limitations
            case relevanceScore = "relevance_score"
            case canonicalTags = "canonical_tags"
            case rationale
        }
    }
}

public enum ZoteroResponseParser {
    public static func createdItemKey(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let success = object["success"] as? [String: String] {
            return success.values.first
        }
        if let successful = object["successful"] as? [String: Any],
           let first = successful.values.first as? [String: Any],
           let key = first["key"] as? String {
            return key
        }
        return nil
    }
}
