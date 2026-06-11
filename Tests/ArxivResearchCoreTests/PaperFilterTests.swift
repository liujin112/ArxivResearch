import Testing
import Foundation
@testable import ArxivResearchCore

@Suite("paper filtering")
struct PaperFilterTests {
    @Test("filters papers by search status tag and date")
    func filtersPapersByVisibleCriteria() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let recent = Paper(
            arxivID: "2601.00001",
            title: "Agent Retrieval",
            abstract: "Uses tools",
            authors: ["Ada"],
            updatedAt: now.addingTimeInterval(-86_400),
            primaryCategory: "cs.AI",
            status: .interested,
            tags: ["agents"]
        )
        let old = Paper(
            arxivID: "2501.00001",
            title: "Vision Benchmark",
            abstract: "Images",
            authors: ["Alan"],
            updatedAt: now.addingTimeInterval(-90 * 86_400),
            primaryCategory: "cs.CV",
            status: .new,
            tags: ["vision"]
        )

        let result = PaperFilter.apply(
            [recent, old],
            criteria: PaperFilterCriteria(
                searchText: "retrieval",
                status: .interested,
                tag: "agents",
                dateRange: .last30Days,
                dateField: .updated
            ),
            now: now
        )

        #expect(result.map(\.arxivID) == ["2601.00001"])
    }

    @Test("filters papers by multiple selected tags")
    func filtersPapersByMultipleSelectedTags() throws {
        let agentPaper = Paper(
            arxivID: "2601.00002",
            title: "Agent Planning",
            abstract: "Planning",
            authors: ["Ada"],
            tags: ["agents", "planning"]
        )
        let visionPaper = Paper(
            arxivID: "2601.00003",
            title: "Vision Policy",
            abstract: "Policy",
            authors: ["Alan"],
            tags: ["vision"]
        )
        let systemsPaper = Paper(
            arxivID: "2601.00004",
            title: "Systems Runtime",
            abstract: "Runtime",
            authors: ["Grace"],
            tags: ["systems"]
        )

        let result = PaperFilter.apply(
            [agentPaper, visionPaper, systemsPaper],
            criteria: PaperFilterCriteria(tags: ["agents", "vision"])
        )

        #expect(result.map(\.arxivID) == ["2601.00002", "2601.00003"])
    }

    @Test("normalizes legacy and new relevance scores for display")
    func normalizesRelevanceScores() throws {
        #expect(RelevanceScore.displayScore(0.7) == 70)
        #expect(RelevanceScore.displayScore(87) == 87)
        #expect(RelevanceScore.displayScore(-10) == 0)
        #expect(RelevanceScore.displayScore(120) == 100)
    }

    @Test("sorts papers by latest personalized relevance score")
    func sortsPapersByRelevanceScore() throws {
        let high = Paper(
            arxivID: "2601.00005",
            title: "Transferable Agent Method",
            abstract: "Method transfer",
            authors: ["Ada"]
        )
        let low = Paper(
            arxivID: "2601.00006",
            title: "Generic Benchmark",
            abstract: "Benchmark",
            authors: ["Alan"]
        )
        let missing = Paper(
            arxivID: "2601.00007",
            title: "Unanalyzed Paper",
            abstract: "No score yet",
            authors: ["Grace"]
        )
        let analyses = [
            high.arxivID: LLMAnalysis(paperID: high.arxivID, oneSentenceSummary: "High", relevanceScore: 91),
            low.arxivID: LLMAnalysis(paperID: low.arxivID, oneSentenceSummary: "Low", relevanceScore: 0.42)
        ]

        let result = PaperFilter.apply(
            [low, missing, high],
            criteria: PaperFilterCriteria(sort: .relevanceScoreDescending),
            analysesByPaperID: analyses
        )

        #expect(result.map(\.arxivID) == ["2601.00005", "2601.00006", "2601.00007"])
    }

    @Test("filters papers by query subscription")
    func filtersPapersByQueryProfileID() throws {
        let selectedProfileID = UUID()
        let otherProfileID = UUID()
        let selected = Paper(
            arxivID: "2601.00008",
            title: "Selected Query Paper",
            abstract: "Agents",
            authors: ["Ada"],
            queryProfileIDs: [selectedProfileID]
        )
        let other = Paper(
            arxivID: "2601.00009",
            title: "Other Query Paper",
            abstract: "Vision",
            authors: ["Alan"],
            queryProfileIDs: [otherProfileID]
        )

        let result = PaperFilter.apply(
            [selected, other],
            criteria: PaperFilterCriteria(queryProfileID: selectedProfileID)
        )

        #expect(result.map(\.arxivID) == ["2601.00008"])
    }

    @Test("filters papers by local added date")
    func filtersPapersByLocalAddedDate() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let june11 = Date(timeIntervalSince1970: 1_781_139_600)
        let june10 = Date(timeIntervalSince1970: 1_781_053_200)
        let selected = Paper(
            arxivID: "2601.00010",
            title: "Today Paper",
            abstract: "Agents",
            authors: ["Ada"],
            addedAt: june11
        )
        let other = Paper(
            arxivID: "2601.00011",
            title: "Yesterday Paper",
            abstract: "Vision",
            authors: ["Alan"],
            addedAt: june10
        )

        let result = PaperFilter.apply(
            [other, selected],
            criteria: PaperFilterCriteria(libraryDate: .day(june11)),
            calendar: calendar
        )

        #expect(result.map(\.arxivID) == ["2601.00010"])
    }

    @Test("filters papers by this week excluding today and yesterday")
    func filtersPapersByThisWeekExcludingTodayAndYesterday() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        let thursday = date("2026-06-11T12:00:00Z")
        let today = paper("2601.00012", addedAt: date("2026-06-11T08:00:00Z"))
        let yesterday = paper("2601.00013", addedAt: date("2026-06-10T08:00:00Z"))
        let earlierThisWeek = paper("2601.00014", addedAt: date("2026-06-09T08:00:00Z"))
        let previousWeek = paper("2601.00015", addedAt: date("2026-06-07T08:00:00Z"))

        let result = PaperFilter.apply(
            [today, yesterday, earlierThisWeek, previousWeek],
            criteria: PaperFilterCriteria(libraryDate: .thisWeek(referenceDate: thursday)),
            calendar: calendar
        )

        #expect(result.map(\.arxivID) == ["2601.00014"])
    }

    @Test("builds library date buckets in expected sidebar order")
    func buildsLibraryDateBucketsInExpectedSidebarOrder() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        let thursday = date("2026-06-11T12:00:00Z")
        let papers = [
            paper("2601.00016", addedAt: date("2026-06-11T08:00:00Z")),
            paper("2601.00017", addedAt: date("2026-06-10T08:00:00Z")),
            paper("2601.00018", addedAt: date("2026-06-09T08:00:00Z")),
            paper("2601.00019", addedAt: date("2026-06-08T08:00:00Z")),
            paper("2601.00020", addedAt: date("2026-06-05T08:00:00Z"))
        ]

        let buckets = PaperLibraryDateBuckets.make(
            for: papers,
            now: thursday,
            calendar: calendar
        )

        #expect(buckets.map(\.title).prefix(4) == ["Today", "Yesterday", "This Week", "Jun 5, 2026"])
        #expect(buckets.map(\.count) == [1, 1, 2, 1])
        #expect(buckets.map(\.filter).prefix(3) == [
            .day(calendar.startOfDay(for: thursday)),
            .day(calendar.startOfDay(for: date("2026-06-10T12:00:00Z"))),
            .thisWeek(referenceDate: calendar.startOfDay(for: thursday))
        ])
    }

    @Test("keeps sidebar date shortcuts and ignores papers without local added date")
    func keepsSidebarDateShortcutsAndIgnoresPapersWithoutAddedAt() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        let thursday = date("2026-06-11T12:00:00Z")
        let paperWithoutAddedAt = Paper(
            arxivID: "2601.00021",
            title: "Paper Without Added Date",
            abstract: "Abstract",
            authors: ["Ada"],
            publishedAt: date("2026-06-05T08:00:00Z"),
            updatedAt: date("2026-06-11T08:00:00Z"),
            addedAt: nil
        )

        let buckets = PaperLibraryDateBuckets.make(
            for: [paperWithoutAddedAt],
            now: thursday,
            calendar: calendar
        )

        #expect(buckets.map(\.title) == ["Today", "Yesterday", "This Week"])
        #expect(buckets.map(\.count) == [0, 0, 0])

        let todayResult = PaperFilter.apply(
            [paperWithoutAddedAt],
            criteria: PaperFilterCriteria(libraryDate: .day(calendar.startOfDay(for: thursday))),
            calendar: calendar
        )
        #expect(todayResult.isEmpty)
    }

    @Test("filters date ranges by selected paper date field")
    func filtersDateRangesBySelectedPaperDateField() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        let thursday = date("2026-06-11T12:00:00Z")
        let publishedToday = Paper(
            arxivID: "2601.00022",
            title: "Published Today",
            abstract: "Abstract",
            authors: ["Ada"],
            publishedAt: date("2026-06-11T08:00:00Z"),
            updatedAt: date("2026-06-11T09:00:00Z"),
            addedAt: date("2026-06-09T08:00:00Z")
        )
        let addedToday = Paper(
            arxivID: "2601.00023",
            title: "Added Today",
            abstract: "Abstract",
            authors: ["Alan"],
            publishedAt: date("2026-06-09T08:00:00Z"),
            updatedAt: date("2026-06-11T09:00:00Z"),
            addedAt: date("2026-06-11T08:00:00Z")
        )

        let publishedResult = PaperFilter.apply(
            [publishedToday, addedToday],
            criteria: PaperFilterCriteria(dateRange: .today, dateField: .published),
            now: thursday,
            calendar: calendar
        )
        let addedResult = PaperFilter.apply(
            [publishedToday, addedToday],
            criteria: PaperFilterCriteria(dateRange: .today, dateField: .added),
            now: thursday,
            calendar: calendar
        )
        let updatedResult = PaperFilter.apply(
            [publishedToday, addedToday],
            criteria: PaperFilterCriteria(dateRange: .today, dateField: .updated),
            now: thursday,
            calendar: calendar
        )

        #expect(publishedResult.map(\.arxivID) == ["2601.00022"])
        #expect(addedResult.map(\.arxivID) == ["2601.00023"])
        #expect(Set(updatedResult.map(\.arxivID)) == Set(["2601.00022", "2601.00023"]))
    }

    private func paper(_ arxivID: String, addedAt: Date) -> Paper {
        Paper(
            arxivID: arxivID,
            title: "Paper \(arxivID)",
            abstract: "Abstract",
            authors: ["Ada"],
            addedAt: addedAt
        )
    }

    private func date(_ iso8601: String) -> Date {
        ISO8601DateFormatter().date(from: iso8601)!
    }
}
