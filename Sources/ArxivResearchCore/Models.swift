import Foundation

public struct QueryProfile: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var rawQuery: String
    public var structuredQueryRoot: StructuredQueryGroup?
    public var usesRawQuery: Bool
    public var refreshIntervalHours: Int
    public var isEnabled: Bool
    public var lastFetchedAt: Date?
    public var maxResults: Int
    public var submittedAfter: Date?

    public init(
        id: UUID = UUID(),
        name: String,
        rawQuery: String,
        structuredQueryRoot: StructuredQueryGroup? = nil,
        usesRawQuery: Bool = true,
        refreshIntervalHours: Int = 24,
        isEnabled: Bool = true,
        lastFetchedAt: Date? = nil,
        maxResults: Int = 50,
        submittedAfter: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.rawQuery = rawQuery
        self.structuredQueryRoot = structuredQueryRoot
        self.usesRawQuery = usesRawQuery
        self.refreshIntervalHours = refreshIntervalHours
        self.isEnabled = isEnabled
        self.lastFetchedAt = lastFetchedAt
        self.maxResults = Self.normalizedMaxResults(maxResults)
        self.submittedAfter = submittedAfter
    }

    public var requestRawQuery: String {
        Self.composeRequestRawQuery(rawQuery: rawQuery, submittedAfter: submittedAfter)
    }

    public static func composeRequestRawQuery(rawQuery: String, submittedAfter: Date?) -> String {
        let trimmedQuery = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let submittedAfter else {
            return trimmedQuery
        }
        let submittedDate = "submittedDate:[\(submittedDateGMTString(from: submittedAfter)) TO *]"
        guard !trimmedQuery.isEmpty else {
            return submittedDate
        }
        return "\(trimmedQuery) AND \(submittedDate)"
    }

    public static func submittedDateGMTString(from date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return String(
            format: "%04d%02d%02d%02d%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0,
            components.hour ?? 0,
            components.minute ?? 0
        )
    }

    private static func normalizedMaxResults(_ maxResults: Int) -> Int {
        min(max(maxResults, 1), 500)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case rawQuery
        case structuredQueryRoot
        case usesRawQuery
        case refreshIntervalHours
        case isEnabled
        case lastFetchedAt
        case maxResults
        case submittedAfter
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        rawQuery = try container.decode(String.self, forKey: .rawQuery)
        refreshIntervalHours = try container.decodeIfPresent(Int.self, forKey: .refreshIntervalHours) ?? 24
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        lastFetchedAt = try container.decodeIfPresent(Date.self, forKey: .lastFetchedAt)
        maxResults = Self.normalizedMaxResults(try container.decodeIfPresent(Int.self, forKey: .maxResults) ?? 50)
        submittedAfter = try container.decodeIfPresent(Date.self, forKey: .submittedAfter)

        if let storedRoot = try container.decodeIfPresent(StructuredQueryGroup.self, forKey: .structuredQueryRoot) {
            structuredQueryRoot = storedRoot
            usesRawQuery = try container.decodeIfPresent(Bool.self, forKey: .usesRawQuery) ?? false
        } else {
            structuredQueryRoot = StructuredArxivQuery.parseRawQuery(rawQuery)
            usesRawQuery = try container.decodeIfPresent(Bool.self, forKey: .usesRawQuery) ?? (structuredQueryRoot == nil)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(rawQuery, forKey: .rawQuery)
        try container.encodeIfPresent(structuredQueryRoot, forKey: .structuredQueryRoot)
        try container.encode(usesRawQuery, forKey: .usesRawQuery)
        try container.encode(refreshIntervalHours, forKey: .refreshIntervalHours)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encodeIfPresent(lastFetchedAt, forKey: .lastFetchedAt)
        try container.encode(Self.normalizedMaxResults(maxResults), forKey: .maxResults)
        try container.encodeIfPresent(submittedAfter, forKey: .submittedAfter)
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
    public var addedAt: Date?
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
        addedAt: Date? = Date(),
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
        self.addedAt = addedAt
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

public struct SyncMetadata: Codable, Hashable, Sendable {
    public var updatedAt: Date
    public var deletedAt: Date?
    public var originDeviceID: String?
    public var revision: Int

    public init(
        updatedAt: Date = Date(),
        deletedAt: Date? = nil,
        originDeviceID: String? = nil,
        revision: Int = 0
    ) {
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.originDeviceID = originDeviceID
        self.revision = revision
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

public enum SyncJobPayload: Codable, Hashable, Sendable {
    case paper(id: String)
    case queryProfile(id: UUID)
    case raw(String)

    enum CodingKeys: String, CodingKey {
        case type
        case id
    }

    enum PayloadType: String, Codable {
        case paper
        case queryProfile
        case raw
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(PayloadType.self, forKey: .type)
        switch type {
        case .paper:
            self = .paper(id: try container.decode(String.self, forKey: .id))
        case .queryProfile:
            self = .queryProfile(id: try container.decode(UUID.self, forKey: .id))
        case .raw:
            self = .raw(try container.decode(String.self, forKey: .id))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .paper(id):
            try container.encode(PayloadType.paper, forKey: .type)
            try container.encode(id, forKey: .id)
        case let .queryProfile(id):
            try container.encode(PayloadType.queryProfile, forKey: .type)
            try container.encode(id, forKey: .id)
        case let .raw(value):
            try container.encode(PayloadType.raw, forKey: .type)
            try container.encode(value, forKey: .id)
        }
    }
}

public enum SyncJobPayloadError: Error, LocalizedError, Sendable {
    case emptyPaperID
    case emptyQueryProfileID
    case unsupportedPaperJobKind(SyncJob.Kind)

    public var errorDescription: String? {
        switch self {
        case .emptyPaperID:
            "Paper job payload is empty."
        case .emptyQueryProfileID:
            "Query profile job payload is empty."
        case let .unsupportedPaperJobKind(kind):
            "\(kind.rawValue) is not a paper-scoped job kind."
        }
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
    public var idempotencyKey: String?
    public var originDeviceID: String?
    public var claimedByDeviceID: String?
    public var claimedAt: Date?
    public var completedAt: Date?

    public init(
        id: UUID = UUID(),
        kind: Kind,
        state: State = .pending,
        payload: Data = Data(),
        attempts: Int = 0,
        scheduledAt: Date = Date(),
        lastError: String? = nil,
        idempotencyKey: String? = nil,
        originDeviceID: String? = nil,
        claimedByDeviceID: String? = nil,
        claimedAt: Date? = nil,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.kind = kind
        self.state = state
        self.payload = payload
        self.attempts = attempts
        self.scheduledAt = scheduledAt
        self.lastError = lastError
        self.idempotencyKey = idempotencyKey
        self.originDeviceID = originDeviceID
        self.claimedByDeviceID = claimedByDeviceID
        self.claimedAt = claimedAt
        self.completedAt = completedAt
    }

    public static func paperJob(
        kind: Kind,
        paperID: String,
        id: UUID = UUID(),
        state: State = .pending,
        scheduledAt: Date = Date(),
        originDeviceID: String? = nil
    ) throws -> SyncJob {
        let trimmed = paperID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw SyncJobPayloadError.emptyPaperID
        }
        guard kind.isPaperScoped else {
            throw SyncJobPayloadError.unsupportedPaperJobKind(kind)
        }
        return SyncJob(
            id: id,
            kind: kind,
            state: state,
            payload: Data(trimmed.utf8),
            scheduledAt: scheduledAt,
            idempotencyKey: "\(kind.rawValue):\(trimmed)",
            originDeviceID: originDeviceID
        )
    }

    public static func queryJob(
        kind: Kind = .fetchArxiv,
        queryProfileID: UUID,
        id: UUID = UUID(),
        state: State = .pending,
        scheduledAt: Date = Date(),
        originDeviceID: String? = nil
    ) -> SyncJob {
        let payload = queryProfileID.uuidString
        return SyncJob(
            id: id,
            kind: kind,
            state: state,
            payload: Data(payload.utf8),
            scheduledAt: scheduledAt,
            idempotencyKey: "\(kind.rawValue):\(payload)",
            originDeviceID: originDeviceID
        )
    }

    public func typedPayload() throws -> SyncJobPayload {
        if let decoded = try? JSONDecoder().decode(SyncJobPayload.self, from: payload) {
            return decoded
        }
        let stringValue = String(data: payload, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if stringValue.isEmpty {
            throw kind == .fetchArxiv ? SyncJobPayloadError.emptyQueryProfileID : SyncJobPayloadError.emptyPaperID
        }
        switch kind {
        case .fetchArxiv:
            guard let id = UUID(uuidString: stringValue) else {
                return .raw(stringValue)
            }
            return .queryProfile(id: id)
        case .summarizeAbstract, .deepRead, .syncNotion, .syncZotero:
            return .paper(id: stringValue)
        }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case kind
        case state
        case payload
        case attempts
        case scheduledAt
        case lastError
        case idempotencyKey
        case originDeviceID
        case claimedByDeviceID
        case claimedAt
        case completedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        kind = try container.decode(Kind.self, forKey: .kind)
        state = try container.decodeIfPresent(State.self, forKey: .state) ?? .pending
        payload = try container.decodeIfPresent(Data.self, forKey: .payload) ?? Data()
        attempts = try container.decodeIfPresent(Int.self, forKey: .attempts) ?? 0
        scheduledAt = try container.decodeIfPresent(Date.self, forKey: .scheduledAt) ?? Date(timeIntervalSince1970: 0)
        lastError = try container.decodeIfPresent(String.self, forKey: .lastError)
        idempotencyKey = try container.decodeIfPresent(String.self, forKey: .idempotencyKey)
        originDeviceID = try container.decodeIfPresent(String.self, forKey: .originDeviceID)
        claimedByDeviceID = try container.decodeIfPresent(String.self, forKey: .claimedByDeviceID)
        claimedAt = try container.decodeIfPresent(Date.self, forKey: .claimedAt)
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encode(state, forKey: .state)
        try container.encode(payload, forKey: .payload)
        try container.encode(attempts, forKey: .attempts)
        try container.encode(scheduledAt, forKey: .scheduledAt)
        try container.encodeIfPresent(lastError, forKey: .lastError)
        try container.encodeIfPresent(idempotencyKey, forKey: .idempotencyKey)
        try container.encodeIfPresent(originDeviceID, forKey: .originDeviceID)
        try container.encodeIfPresent(claimedByDeviceID, forKey: .claimedByDeviceID)
        try container.encodeIfPresent(claimedAt, forKey: .claimedAt)
        try container.encodeIfPresent(completedAt, forKey: .completedAt)
    }
}

public extension SyncJob.Kind {
    var isPaperScoped: Bool {
        switch self {
        case .summarizeAbstract, .deepRead, .syncNotion, .syncZotero:
            true
        case .fetchArxiv:
            false
        }
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
