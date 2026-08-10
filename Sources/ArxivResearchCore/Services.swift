import Foundation

public final class ArxivHTTPClient: ArxivClient, @unchecked Sendable {
    private let session: URLSession
    private let parser: ArxivAtomParser

    public init(session: URLSession = .shared, parser: ArxivAtomParser = ArxivAtomParser()) {
        self.session = session
        self.parser = parser
    }

    public func search(_ request: ArxivAPIRequest) async throws -> ArxivFeed {
        let url = try request.url()
        let (data, response) = try await session.data(from: url)
        if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode) {
            throw ArxivError.apiError("HTTP \(httpResponse.statusCode)")
        }
        let feed = try parser.parse(data)
        if feed.isError {
            throw ArxivError.apiError(feed.errorMessage ?? "Unknown arXiv error")
        }
        return feed
    }
}

public struct SimpleTagCanonicalizer: TagCanonicalizer {
    public init() {}

    public func canonicalize(suggestedTags: [String], existing: [CanonicalTag]) -> [CanonicalTag] {
        var tagsByKey = Dictionary(uniqueKeysWithValues: existing.map { (Self.key($0.name), $0) })
        for suggested in suggestedTags {
            let normalized = Self.normalizedName(suggested)
            guard !normalized.isEmpty else { continue }
            let key = Self.key(normalized)
            if var tag = tagsByKey[key] {
                if !tag.aliases.contains(suggested), suggested != tag.name {
                    tag.aliases.append(suggested)
                }
                tagsByKey[key] = tag
            } else {
                tagsByKey[key] = CanonicalTag(name: normalized, aliases: suggested == normalized ? [] : [suggested])
            }
        }
        return tagsByKey.values.sorted { $0.name < $1.name }
    }

    private static func displayName(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func normalizedName(_ value: String) -> String {
        var name = displayName(value)
        if name.hasSuffix("s"), name.count > 3 {
            name.removeLast()
        }
        return name
    }

    private static func key(_ value: String) -> String {
        normalizedName(value).replacingOccurrences(of: #"[\s_-]+"#, with: "-", options: .regularExpression)
    }
}

public final class URLContentExtractor: ContentExtractor, @unchecked Sendable {
    private let session: URLSession
    private let htmlConverter: HTMLToMarkdownConverter
    private let pdfExtractor: PDFTextExtractor

    public init(
        session: URLSession = .shared,
        htmlConverter: HTMLToMarkdownConverter = HTMLToMarkdownConverter(),
        pdfExtractor: PDFTextExtractor = PDFTextExtractor()
    ) {
        self.session = session
        self.htmlConverter = htmlConverter
        self.pdfExtractor = pdfExtractor
    }

    public func markdown(for paper: Paper) async throws -> ExtractedContent {
        if let htmlURL = htmlURL(for: paper) {
            do {
                let (data, _) = try await session.data(from: htmlURL)
                if let html = String(data: data, encoding: .utf8), !html.isEmpty {
                    return ExtractedContent(markdown: htmlConverter.convert(html), sourceKind: .html)
                }
            } catch {
                // Fall back to PDF below.
            }
        }
        guard let pdfURL = paper.pdfURL else {
            throw ContentExtractionError.noSourceAvailable
        }
        let (data, _) = try await session.data(from: pdfURL)
        return ExtractedContent(markdown: try pdfExtractor.extractMarkdown(from: data), sourceKind: .pdf)
    }

    private func htmlURL(for paper: Paper) -> URL? {
        let rawID = paper.versionedID ?? paper.arxivID
        guard let versionedID = rawID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return nil
        }
        return URL(string: "https://arxiv.org/html/\(versionedID)")
    }
}

public struct ResearchAutomationProfileFailure: Hashable, Sendable {
    public var profileID: QueryProfile.ID
    public var profileName: String
    public var message: String

    public init(profileID: QueryProfile.ID, profileName: String, message: String) {
        self.profileID = profileID
        self.profileName = profileName
        self.message = message
    }
}

public struct ResearchAutomationRunReport: Hashable, Sendable {
    public var attemptedProfileIDs: [QueryProfile.ID] = []
    public var succeededProfileIDs: [QueryProfile.ID] = []
    public var skippedProfileIDs: [QueryProfile.ID] = []
    public var failures: [ResearchAutomationProfileFailure] = []

    public init() {}
}

public enum ResearchAutomationError: Error, LocalizedError, Sendable {
    case profileNotFound(QueryProfile.ID)

    public var errorDescription: String? {
        switch self {
        case let .profileNotFound(id):
            "Subscription \(id.uuidString) no longer exists."
        }
    }
}

@MainActor
public final class ResearchAutomationService {
    private let store: SQLiteResearchStore
    private let arxivClient: any ArxivClient
    private let queueSummaries: Bool
    private let interProfileDelay: Duration

    public init(
        store: SQLiteResearchStore,
        arxivClient: any ArxivClient = ArxivHTTPClient(),
        queueSummaries: Bool = true,
        interProfileDelay: Duration = .seconds(3)
    ) {
        self.store = store
        self.arxivClient = arxivClient
        self.queueSummaries = queueSummaries
        self.interProfileDelay = interProfileDelay
    }

    @discardableResult
    public func runOnce(now: Date = Date()) async throws -> ResearchAutomationRunReport {
        let profiles = try store.fetchQueryProfiles().filter { profile in
            guard profile.isEnabled else { return false }
            guard let lastFetchedAt = profile.lastFetchedAt else { return true }
            return now.timeIntervalSince(lastFetchedAt) >= Double(profile.refreshIntervalHours * 3600)
        }

        var report = ResearchAutomationRunReport()
        for (index, profile) in profiles.enumerated() {
            report.attemptedProfileIDs.append(profile.id)
            do {
                if try await runProfile(profileID: profile.id, now: now) {
                    report.succeededProfileIDs.append(profile.id)
                } else {
                    report.skippedProfileIDs.append(profile.id)
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                report.failures.append(ResearchAutomationProfileFailure(
                    profileID: profile.id,
                    profileName: profile.name,
                    message: error.localizedDescription
                ))
            }
            if index < profiles.index(before: profiles.endIndex) {
                try await Task.sleep(for: interProfileDelay)
            }
        }

        if queueSummaries {
            _ = try queueUnanalyzedSummaries()
        }
        return report
    }

    /// Fetches one subscription under a cross-process lease. Returns `false`
    /// when another app/helper process already owns the active lease.
    @discardableResult
    public func runProfile(
        profileID: QueryProfile.ID,
        now: Date = Date(),
        leaseOwnerID: String = "automation-\(UUID().uuidString)"
    ) async throws -> Bool {
        guard let profile = try store.fetchQueryProfile(id: profileID) else {
            throw ResearchAutomationError.profileNotFound(profileID)
        }
        guard try store.claimQueryFetch(profileID: profileID, ownerID: leaseOwnerID, now: now) else {
            return false
        }
        defer { try? store.releaseQueryFetch(profileID: profileID, ownerID: leaseOwnerID) }

        let request = ArxivAPIRequest(searchQuery: .raw(profile.requestRawQuery), maxResults: profile.maxResults)
        let feed = try await arxivClient.search(request)
        var fetchedPaperIDs = Set<Paper.ID>()
        for entry in feed.entries {
            var paper = entry.asPaper(queryProfileID: profile.id)
            paper.addedAt = now
            if let existing = try store.fetchPaper(arxivID: paper.arxivID) {
                paper.queryProfileIDs = Array(Set(existing.queryProfileIDs + [profile.id]))
                paper.status = existing.status
                paper.tags = existing.tags
                paper.zoteroKey = existing.zoteroKey
                paper.notionPageID = existing.notionPageID
                paper.addedAt = existing.addedAt ?? now
            }
            try store.upsertPaper(paper)
            fetchedPaperIDs.insert(paper.arxivID)
        }
        if queueSummaries {
            _ = try queueUnanalyzedSummaries(paperIDs: fetchedPaperIDs)
        }
        if var latestProfile = try store.fetchQueryProfile(id: profileID) {
            latestProfile.lastFetchedAt = now
            try store.upsertQueryProfile(latestProfile)
        }
        return true
    }

    @discardableResult
    public func queueUnanalyzedSummaries(limit: Int = 500, paperIDs: Set<Paper.ID>? = nil) throws -> [SyncJob] {
        guard queueSummaries else {
            return []
        }
        let papers = try store.fetchPapers()
        var queued: [SyncJob] = []
        for paper in papers {
            guard queued.count < limit else { break }
            if let paperIDs, !paperIDs.contains(paper.arxivID) {
                continue
            }
            guard try store.latestAnalysis(for: paper.arxivID) == nil else {
                continue
            }
            let job = try store.enqueueIfNeeded(try SyncJob.paperJob(kind: .summarizeAbstract, paperID: paper.arxivID))
            if job.state == .pending {
                queued.append(job)
            }
        }
        return queued
    }
}

public enum AppEnvironment {
    public static func applicationSupportDirectory() throws -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = base.appendingPathComponent("ArxivResearch", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    public static func defaultDatabaseURL() throws -> URL {
        try applicationSupportDirectory().appendingPathComponent("arxiv-research.sqlite")
    }
}
