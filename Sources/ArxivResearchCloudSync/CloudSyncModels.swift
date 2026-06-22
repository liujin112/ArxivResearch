import Foundation
import ArxivResearchCore

public enum CloudSyncRecordKind: String, Codable, CaseIterable, Hashable, Sendable {
    case paper
    case queryProfile
    case analysis
    case deepRead
    case job
}

public struct CloudSyncRecordName: RawRepresentable, Codable, Hashable, Sendable {
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static func paper(_ arxivID: String) -> CloudSyncRecordName {
        CloudSyncRecordName(rawValue: "paper_\(sanitize(arxivID))")
    }

    public static func queryProfile(_ id: UUID) -> CloudSyncRecordName {
        CloudSyncRecordName(rawValue: "query_\(sanitize(id.uuidString))")
    }

    public static func analysis(_ id: UUID) -> CloudSyncRecordName {
        CloudSyncRecordName(rawValue: "analysis_\(sanitize(id.uuidString))")
    }

    public static func deepRead(_ id: UUID) -> CloudSyncRecordName {
        CloudSyncRecordName(rawValue: "deepRead_\(sanitize(id.uuidString))")
    }

    public static func job(idempotencyKey: String) -> CloudSyncRecordName {
        CloudSyncRecordName(rawValue: "job_\(sanitize(idempotencyKey))")
    }

    public static func job(id: UUID) -> CloudSyncRecordName {
        CloudSyncRecordName(rawValue: "job_\(sanitize(id.uuidString))")
    }

    public static func sanitize(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        let scalars = value.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "_"
        }
        let collapsed = String(scalars)
            .replacingOccurrences(of: "_+", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return collapsed.isEmpty ? "record" : collapsed
    }
}

public struct CloudPaperRecord: Codable, Hashable, Sendable {
    public var recordName: String
    public var metadata: SyncMetadata
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
    public var absURLString: String?
    public var pdfURLString: String?
    public var queryProfileIDs: [UUID]
    public var status: PaperStatus
    public var tags: [String]
    public var zoteroKey: String?
    public var notionPageID: String?

    public init(paper: Paper, metadata: SyncMetadata = SyncMetadata()) {
        recordName = CloudSyncRecordName.paper(paper.arxivID).rawValue
        self.metadata = metadata
        arxivID = paper.arxivID
        versionedID = paper.versionedID
        title = paper.title
        abstract = paper.abstract
        authors = paper.authors
        publishedAt = paper.publishedAt
        updatedAt = paper.updatedAt
        addedAt = paper.addedAt
        primaryCategory = paper.primaryCategory
        categories = paper.categories
        absURLString = paper.absURL?.absoluteString
        pdfURLString = paper.pdfURL?.absoluteString
        queryProfileIDs = paper.queryProfileIDs
        status = paper.status
        tags = paper.tags
        zoteroKey = paper.zoteroKey
        notionPageID = paper.notionPageID
    }

    public func paper() -> Paper {
        Paper(
            arxivID: arxivID,
            versionedID: versionedID,
            title: title,
            abstract: abstract,
            authors: authors,
            publishedAt: publishedAt,
            updatedAt: updatedAt,
            addedAt: addedAt,
            primaryCategory: primaryCategory,
            categories: categories,
            absURL: absURLString.flatMap(URL.init(string:)),
            pdfURL: pdfURLString.flatMap(URL.init(string:)),
            queryProfileIDs: queryProfileIDs,
            status: status,
            tags: tags,
            zoteroKey: zoteroKey,
            notionPageID: notionPageID
        )
    }
}

public struct CloudQueryProfileRecord: Codable, Hashable, Sendable {
    public var recordName: String
    public var metadata: SyncMetadata
    public var profile: QueryProfile

    public init(profile: QueryProfile, metadata: SyncMetadata = SyncMetadata()) {
        recordName = CloudSyncRecordName.queryProfile(profile.id).rawValue
        self.metadata = metadata
        self.profile = profile
    }
}

public struct CloudAnalysisRecord: Codable, Hashable, Sendable {
    public var recordName: String
    public var metadata: SyncMetadata
    public var analysis: LLMAnalysis

    public init(analysis: LLMAnalysis, metadata: SyncMetadata = SyncMetadata()) {
        recordName = CloudSyncRecordName.analysis(analysis.id).rawValue
        self.metadata = metadata
        self.analysis = analysis
    }
}

public struct CloudDeepReadRecord: Codable, Hashable, Sendable {
    public var recordName: String
    public var metadata: SyncMetadata
    public var report: DeepReadReport

    public init(report: DeepReadReport, metadata: SyncMetadata = SyncMetadata()) {
        recordName = CloudSyncRecordName.deepRead(report.id).rawValue
        self.metadata = metadata
        self.report = report
    }
}

public enum CloudJobRecordError: Error, LocalizedError, Sendable {
    case missingTypedPayload

    public var errorDescription: String? {
        switch self {
        case .missingTypedPayload:
            "Cloud job records require a typed payload."
        }
    }
}

public struct CloudJobRecord: Codable, Hashable, Sendable {
    public var recordName: String
    public var jobID: UUID
    public var kind: SyncJob.Kind
    public var state: SyncJob.State
    public var typedPayload: SyncJobPayload
    public var attempts: Int
    public var scheduledAt: Date
    public var lastError: String?
    public var idempotencyKey: String?
    public var originDeviceID: String?
    public var claimedByDeviceID: String?
    public var claimedAt: Date?
    public var completedAt: Date?

    public init(
        recordName: String,
        jobID: UUID,
        kind: SyncJob.Kind,
        state: SyncJob.State,
        typedPayload: SyncJobPayload,
        attempts: Int,
        scheduledAt: Date,
        lastError: String?,
        idempotencyKey: String?,
        originDeviceID: String?,
        claimedByDeviceID: String?,
        claimedAt: Date?,
        completedAt: Date?
    ) {
        self.recordName = recordName
        self.jobID = jobID
        self.kind = kind
        self.state = state
        self.typedPayload = typedPayload
        self.attempts = attempts
        self.scheduledAt = scheduledAt
        self.lastError = lastError
        self.idempotencyKey = idempotencyKey
        self.originDeviceID = originDeviceID
        self.claimedByDeviceID = claimedByDeviceID
        self.claimedAt = claimedAt
        self.completedAt = completedAt
    }

    public init(job: SyncJob) throws {
        let typedPayload = try job.typedPayload()
        let key = job.idempotencyKey ?? Self.idempotencyKey(kind: job.kind, payload: typedPayload)
        self.init(
            recordName: key.map { CloudSyncRecordName.job(idempotencyKey: $0).rawValue } ?? CloudSyncRecordName.job(id: job.id).rawValue,
            jobID: job.id,
            kind: job.kind,
            state: job.state,
            typedPayload: typedPayload,
            attempts: job.attempts,
            scheduledAt: job.scheduledAt,
            lastError: job.lastError,
            idempotencyKey: key,
            originDeviceID: job.originDeviceID,
            claimedByDeviceID: job.claimedByDeviceID,
            claimedAt: job.claimedAt,
            completedAt: job.completedAt
        )
    }

    public func job() throws -> SyncJob {
        let payload: Data
        switch typedPayload {
        case let .paper(id), let .raw(id):
            payload = Data(id.utf8)
        case let .queryProfile(id):
            payload = Data(id.uuidString.utf8)
        }
        return SyncJob(
            id: jobID,
            kind: kind,
            state: state,
            payload: payload,
            attempts: attempts,
            scheduledAt: scheduledAt,
            lastError: lastError,
            idempotencyKey: idempotencyKey ?? Self.idempotencyKey(kind: kind, payload: typedPayload),
            originDeviceID: originDeviceID,
            claimedByDeviceID: claimedByDeviceID,
            claimedAt: claimedAt,
            completedAt: completedAt
        )
    }

    public static func idempotencyKey(kind: SyncJob.Kind, payload: SyncJobPayload) -> String? {
        switch payload {
        case let .paper(id):
            "\(kind.rawValue):\(id)"
        case let .queryProfile(id):
            "\(kind.rawValue):\(id.uuidString)"
        case let .raw(value):
            value.isEmpty ? nil : "\(kind.rawValue):\(value)"
        }
    }
}

public struct CloudJobLeasePolicy: Codable, Hashable, Sendable {
    public var staleAfter: TimeInterval

    public init(staleAfter: TimeInterval = 15 * 60) {
        self.staleAfter = staleAfter
    }

    public func canClaim(_ job: CloudJobRecord, by deviceID: String, now: Date = Date()) -> Bool {
        switch job.state {
        case .pending:
            return job.scheduledAt <= now
        case .running:
            guard job.claimedByDeviceID != deviceID else {
                return true
            }
            guard let claimedAt = job.claimedAt else {
                return true
            }
            return now.timeIntervalSince(claimedAt) > staleAfter
        case .succeeded, .failed:
            return false
        }
    }

    public func claimed(_ job: CloudJobRecord, by deviceID: String, now: Date = Date()) -> CloudJobRecord {
        var claimed = job
        claimed.state = .running
        claimed.claimedByDeviceID = deviceID
        claimed.claimedAt = now
        claimed.completedAt = nil
        claimed.lastError = nil
        return claimed
    }
}
