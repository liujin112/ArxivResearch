import Foundation

public final class ArxivHTTPClient: ArxivClient {
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

public final class ResearchAutomationService {
    private let store: SQLiteResearchStore
    private let arxivClient: any ArxivClient
    private let queueSummaries: Bool

    public init(
        store: SQLiteResearchStore,
        arxivClient: any ArxivClient = ArxivHTTPClient(),
        queueSummaries: Bool = true
    ) {
        self.store = store
        self.arxivClient = arxivClient
        self.queueSummaries = queueSummaries
    }

    public func runOnce(now: Date = Date()) async throws {
        let profiles = try store.fetchQueryProfiles().filter { profile in
            guard profile.isEnabled else { return false }
            guard let lastFetchedAt = profile.lastFetchedAt else { return true }
            return now.timeIntervalSince(lastFetchedAt) >= Double(profile.refreshIntervalHours * 3600)
        }

        for profile in profiles {
            let request = ArxivAPIRequest(searchQuery: .raw(profile.rawQuery), maxResults: 50)
            let feed = try await arxivClient.search(request)
            for entry in feed.entries {
                var paper = entry.asPaper(queryProfileID: profile.id)
                paper.addedAt = now
                if let existing = try store.fetchPaper(arxivID: paper.arxivID) {
                    paper.queryProfileIDs = Array(Set(existing.queryProfileIDs + [profile.id]))
                    paper.status = existing.status
                    paper.tags = existing.tags
                    paper.zoteroKey = existing.zoteroKey
                    paper.notionPageID = existing.notionPageID
                    paper.addedAt = existing.addedAt ?? existing.updatedAt ?? existing.publishedAt ?? now
                }
                try store.upsertPaper(paper)
                if queueSummaries {
                    try store.enqueue(SyncJob(kind: .summarizeAbstract, payload: Data(entry.arxivID.utf8)))
                }
            }
            var updatedProfile = profile
            updatedProfile.lastFetchedAt = now
            try store.upsertQueryProfile(updatedProfile)
            try await Task.sleep(for: .seconds(3))
        }
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
