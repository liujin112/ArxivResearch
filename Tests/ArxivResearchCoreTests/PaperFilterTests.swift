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
                dateRange: .last30Days
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
}
