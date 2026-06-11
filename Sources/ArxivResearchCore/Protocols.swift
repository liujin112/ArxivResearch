import Foundation

public protocol ArxivClient {
    func search(_ request: ArxivAPIRequest) async throws -> ArxivFeed
}

public protocol LLMProvider: Sendable {
    var config: ProviderConfig { get }
    func buildRequest(apiKey: String, payload: LLMPromptPayload) throws -> URLRequest
    func complete(apiKey: String, payload: LLMPromptPayload) async throws -> String
}

public protocol ContentExtractor: Sendable {
    func markdown(for paper: Paper) async throws -> ExtractedContent
}

public protocol TagCanonicalizer {
    func canonicalize(suggestedTags: [String], existing: [CanonicalTag]) -> [CanonicalTag]
}

public protocol NotionSyncClient: Sendable {
    func buildCreateDatabaseRequest() throws -> URLRequest
    func buildCreatePageRequest(paper: Paper, analysis: LLMAnalysis?, deepRead: DeepReadReport?) throws -> URLRequest
    func buildUpsertPageRequest(paper: Paper, analysis: LLMAnalysis?, deepRead: DeepReadReport?) throws -> URLRequest
    func buildUpdatePageRequest(pageID: String, paper: Paper, analysis: LLMAnalysis?, deepRead: DeepReadReport?) throws -> URLRequest
    func buildAppendPageContentRequest(pageID: String, paper: Paper, analysis: LLMAnalysis?, deepRead: DeepReadReport?) throws -> URLRequest
}

public protocol ZoteroSyncClient: Sendable {
    func buildCreateItemRequest(paper: Paper, analysis: LLMAnalysis?) throws -> URLRequest
    func buildCreateNoteRequest(parentItemKey: String, paper: Paper, analysis: LLMAnalysis?, deepRead: DeepReadReport?) throws -> URLRequest
    func buildCreatePDFAttachmentRequest(parentItemKey: String, paper: Paper) throws -> URLRequest
}

public protocol JobQueue {
    func enqueue(_ job: SyncJob) throws
    func nextPendingJob(now: Date) throws -> SyncJob?
    func mark(_ jobID: UUID, state: SyncJob.State, error: String?) throws
}

public protocol Scheduler {
    func dueProfiles(now: Date) throws -> [QueryProfile]
}

public struct ExtractedContent: Codable, Hashable, Sendable {
    public var markdown: String
    public var sourceKind: DeepReadReport.SourceKind

    public init(markdown: String, sourceKind: DeepReadReport.SourceKind) {
        self.markdown = markdown
        self.sourceKind = sourceKind
    }
}
