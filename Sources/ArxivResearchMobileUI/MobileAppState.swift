import Foundation
import SwiftUI
import ArxivResearchCore

@MainActor
public final class MobileAppState: ObservableObject {
    @Published public var papers: [Paper] = []
    @Published public var queryProfiles: [QueryProfile] = []
    @Published public var jobs: [SyncJob] = []
    @Published public var selectedPaperID: Paper.ID?
    @Published public var searchText = ""
    @Published public var statusFilter: PaperStatus?
    @Published public var tagFilter: String?
    @Published public var latestAnalysesByPaperID: [Paper.ID: LLMAnalysis] = [:]
    @Published public var latestDeepReadsByPaperID: [Paper.ID: DeepReadReport] = [:]
    @Published public var statusMessage = "Loading library"

    private var store: SQLiteResearchStore?

    public init() {
        load()
    }

    public var selectedPaper: Paper? {
        papers.first { $0.id == selectedPaperID }
    }

    public var availableTags: [String] {
        Array(Set(papers.flatMap(\.tags) + latestAnalysesByPaperID.values.flatMap(\.canonicalTags))).sorted()
    }

    public var filteredPapers: [Paper] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return papers.filter { paper in
            if let statusFilter, paper.status != statusFilter {
                return false
            }
            if let tagFilter, !paper.tags.contains(tagFilter), !(latestAnalysesByPaperID[paper.id]?.canonicalTags.contains(tagFilter) ?? false) {
                return false
            }
            guard !query.isEmpty else {
                return true
            }
            return paper.title.localizedCaseInsensitiveContains(query)
                || paper.abstract.localizedCaseInsensitiveContains(query)
                || paper.authors.contains { $0.localizedCaseInsensitiveContains(query) }
                || paper.arxivID.lowercased().contains(query)
        }
    }

    public func refresh() {
        guard let store else {
            load()
            return
        }
        do {
            papers = try store.fetchPapers()
            queryProfiles = try store.fetchQueryProfiles()
            jobs = try store.fetchJobs(limit: 100)
            latestAnalysesByPaperID = try Dictionary(uniqueKeysWithValues: papers.compactMap { paper in
                guard let analysis = try store.latestAnalysis(for: paper.id) else {
                    return nil
                }
                return (paper.id, analysis)
            })
            latestDeepReadsByPaperID = try Dictionary(uniqueKeysWithValues: papers.compactMap { paper in
                guard let deepRead = try store.latestDeepRead(for: paper.id) else {
                    return nil
                }
                return (paper.id, deepRead)
            })
            if selectedPaperID == nil || !papers.contains(where: { $0.id == selectedPaperID }) {
                selectedPaperID = papers.first?.id
            }
            statusMessage = papers.isEmpty ? "No papers in local library" : "Library refreshed"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    public func selectPaper(_ paper: Paper) {
        selectedPaperID = paper.id
    }

    public func clearFilters() {
        searchText = ""
        statusFilter = nil
        tagFilter = nil
    }

    public func queueSummary(for paper: Paper) {
        enqueue(kind: .summarizeAbstract, paperID: paper.id, successMessage: "Summary queued for \(paper.arxivID)")
    }

    public func queueDeepRead(for paper: Paper) {
        do {
            var queuedPaper = paper
            queuedPaper.status = .deepReading
            try store?.upsertPaper(queuedPaper)
            if let index = papers.firstIndex(where: { $0.id == paper.id }) {
                papers[index] = queuedPaper
            }
            enqueue(kind: .deepRead, paperID: paper.id, successMessage: "Deep read queued for \(paper.arxivID)")
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    public func latestAnalysis(for paper: Paper) -> LLMAnalysis? {
        latestAnalysesByPaperID[paper.id]
    }

    public func latestDeepRead(for paper: Paper) -> DeepReadReport? {
        latestDeepReadsByPaperID[paper.id]
    }

    private func load() {
        do {
            let databaseURL = try AppEnvironment.defaultDatabaseURL()
            let store = try SQLiteResearchStore(path: databaseURL)
            self.store = store
            try seedFixturesIfNeeded(in: store)
            refresh()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func seedFixturesIfNeeded(in store: SQLiteResearchStore) throws {
        guard try store.fetchPapers().isEmpty else {
            return
        }
        var first = Paper.fixture(arxivID: "2401.00001")
        first.tags = ["llm", "mobile"]
        var second = Paper.fixture(arxivID: "2401.00002")
        second.title = "A Test Paper for Local Sync"
        second.abstract = "A second compact fixture used when the mobile companion has no local cache yet."
        second.tags = ["sync"]
        try store.upsertPaper(first)
        try store.upsertPaper(second)
    }

    private func enqueue(kind: SyncJob.Kind, paperID: Paper.ID, successMessage: String) {
        do {
            try store?.enqueue(SyncJob.paperJob(kind: kind, paperID: paperID))
            jobs = try store?.fetchJobs(limit: 100) ?? []
            statusMessage = successMessage
        } catch {
            statusMessage = error.localizedDescription
        }
    }
}
