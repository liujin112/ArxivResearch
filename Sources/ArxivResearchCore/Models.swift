import Foundation

public struct QueryProfile: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var rawQuery: String
    public var refreshIntervalHours: Int
    public var isEnabled: Bool
    public var lastFetchedAt: Date?

    public init(
        id: UUID = UUID(),
        name: String,
        rawQuery: String,
        refreshIntervalHours: Int = 24,
        isEnabled: Bool = true,
        lastFetchedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.rawQuery = rawQuery
        self.refreshIntervalHours = refreshIntervalHours
        self.isEnabled = isEnabled
        self.lastFetchedAt = lastFetchedAt
    }
}

public enum PaperStatus: String, Codable, CaseIterable, Hashable, Sendable {
    case new
    case summarized
    case interested
    case deepReading
    case deepRead
    case archived
}

public struct Paper: Identifiable, Codable, Hashable, Sendable {
    public var id: String { arxivID }
    public var arxivID: String
    public var versionedID: String?
    public var title: String
    public var abstract: String
    public var authors: [String]
    public var publishedAt: Date?
    public var updatedAt: Date?
    public var primaryCategory: String?
    public var categories: [String]
    public var absURL: URL?
    public var pdfURL: URL?
    public var queryProfileIDs: [UUID]
    public var status: PaperStatus
    public var tags: [String]
    public var zoteroKey: String?
    public var notionPageID: String?

    public init(
        arxivID: String,
        versionedID: String? = nil,
        title: String,
        abstract: String,
        authors: [String],
        publishedAt: Date? = nil,
        updatedAt: Date? = nil,
        primaryCategory: String? = nil,
        categories: [String] = [],
        absURL: URL? = nil,
        pdfURL: URL? = nil,
        queryProfileIDs: [UUID] = [],
        status: PaperStatus = .new,
        tags: [String] = [],
        zoteroKey: String? = nil,
        notionPageID: String? = nil
    ) {
        self.arxivID = arxivID
        self.versionedID = versionedID
        self.title = title
        self.abstract = abstract
        self.authors = authors
        self.publishedAt = publishedAt
        self.updatedAt = updatedAt
        self.primaryCategory = primaryCategory
        self.categories = categories
        self.absURL = absURL
        self.pdfURL = pdfURL
        self.queryProfileIDs = queryProfileIDs
        self.status = status
        self.tags = tags
        self.zoteroKey = zoteroKey
        self.notionPageID = notionPageID
    }
}

public struct LLMAnalysis: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var paperID: String
    public var oneSentenceSummary: String
    public var keyContributions: [String]
    public var methods: [String]
    public var results: [String]
    public var limitations: [String]
    public var relevanceScore: Double
    public var canonicalTags: [String]
    public var rationale: String
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        paperID: String,
        oneSentenceSummary: String,
        keyContributions: [String] = [],
        methods: [String] = [],
        results: [String] = [],
        limitations: [String] = [],
        relevanceScore: Double = 0,
        canonicalTags: [String] = [],
        rationale: String = "",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.paperID = paperID
        self.oneSentenceSummary = oneSentenceSummary
        self.keyContributions = keyContributions
        self.methods = methods
        self.results = results
        self.limitations = limitations
        self.relevanceScore = relevanceScore
        self.canonicalTags = canonicalTags
        self.rationale = rationale
        self.createdAt = createdAt
    }
}

public struct CanonicalTag: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var aliases: [String]
    public var createdAt: Date

    public init(id: UUID = UUID(), name: String, aliases: [String] = [], createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.aliases = aliases
        self.createdAt = createdAt
    }
}

public struct DeepReadReport: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var paperID: String
    public var prompt: String
    public var markdown: String
    public var sourceKind: SourceKind
    public var createdAt: Date

    public enum SourceKind: String, Codable, Hashable, Sendable {
        case html
        case pdf
        case mixed
    }

    public init(
        id: UUID = UUID(),
        paperID: String,
        prompt: String,
        markdown: String,
        sourceKind: SourceKind,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.paperID = paperID
        self.prompt = prompt
        self.markdown = markdown
        self.sourceKind = sourceKind
        self.createdAt = createdAt
    }
}

public struct SyncJob: Identifiable, Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Hashable, Sendable {
        case fetchArxiv
        case summarizeAbstract
        case deepRead
        case syncNotion
        case syncZotero
    }

    public enum State: String, Codable, Hashable, Sendable {
        case pending
        case running
        case succeeded
        case failed
    }

    public var id: UUID
    public var kind: Kind
    public var state: State
    public var payload: Data
    public var attempts: Int
    public var scheduledAt: Date
    public var lastError: String?

    public init(
        id: UUID = UUID(),
        kind: Kind,
        state: State = .pending,
        payload: Data = Data(),
        attempts: Int = 0,
        scheduledAt: Date = Date(),
        lastError: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.state = state
        self.payload = payload
        self.attempts = attempts
        self.scheduledAt = scheduledAt
        self.lastError = lastError
    }
}

public extension Paper {
    static func fixture(arxivID: String = "2401.00001") -> Paper {
        Paper(
            arxivID: arxivID,
            versionedID: "\(arxivID)v1",
            title: "A Test Paper",
            abstract: "A compact abstract for testing.",
            authors: ["Ada Lovelace", "Alan Turing"],
            publishedAt: Date(timeIntervalSince1970: 1_704_067_200),
            updatedAt: Date(timeIntervalSince1970: 1_704_067_200),
            primaryCategory: "cs.AI",
            categories: ["cs.AI"],
            absURL: URL(string: "https://arxiv.org/abs/\(arxivID)"),
            pdfURL: URL(string: "https://arxiv.org/pdf/\(arxivID)")
        )
    }
}

public extension LLMAnalysis {
    static func fixture(tags: [String] = ["llm"]) -> LLMAnalysis {
        LLMAnalysis(
            paperID: "2401.00001",
            oneSentenceSummary: "This paper is useful for testing.",
            keyContributions: ["A test contribution"],
            methods: ["A test method"],
            results: ["A test result"],
            limitations: ["A test limitation"],
            relevanceScore: 0.8,
            canonicalTags: tags,
            rationale: "Synthetic fixture."
        )
    }
}
