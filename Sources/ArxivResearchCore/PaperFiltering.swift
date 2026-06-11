import Foundation

public enum PaperDateRange: String, CaseIterable, Codable, Hashable, Sendable {
    case all
    case last7Days
    case last30Days
    case lastYear

    public var displayName: String {
        switch self {
        case .all:
            "All dates"
        case .last7Days:
            "Last 7 days"
        case .last30Days:
            "Last 30 days"
        case .lastYear:
            "Last year"
        }
    }

    func contains(_ date: Date?, now: Date) -> Bool {
        guard self != .all else { return true }
        guard let date else { return false }
        let interval: TimeInterval
        switch self {
        case .all:
            return true
        case .last7Days:
            interval = 7 * 86_400
        case .last30Days:
            interval = 30 * 86_400
        case .lastYear:
            interval = 365 * 86_400
        }
        return date >= now.addingTimeInterval(-interval)
    }
}

public struct PaperFilterCriteria: Codable, Hashable, Sendable {
    public var searchText: String
    public var status: PaperStatus?
    public var tag: String?
    public var tags: Set<String>
    public var dateRange: PaperDateRange
    public var sort: PaperSortOption

    public init(
        searchText: String = "",
        status: PaperStatus? = nil,
        tag: String? = nil,
        tags: Set<String> = [],
        dateRange: PaperDateRange = .all,
        sort: PaperSortOption = .dateDescending
    ) {
        self.searchText = searchText
        self.status = status
        self.tag = tag
        self.tags = tags
        self.dateRange = dateRange
        self.sort = sort
    }
}

public enum PaperSortOption: String, CaseIterable, Codable, Hashable, Sendable {
    case dateDescending
    case relevanceScoreDescending

    public var displayName: String {
        switch self {
        case .dateDescending:
            "Latest"
        case .relevanceScoreDescending:
            "Score"
        }
    }
}

public enum RelevanceScore {
    public static func normalized(_ rawScore: Double?) -> Double {
        guard let rawScore else { return -1 }
        let score = rawScore <= 1 ? rawScore * 100 : rawScore
        return min(max(score, 0), 100)
    }

    public static func displayScore(_ rawScore: Double) -> Int {
        Int(normalized(rawScore).rounded())
    }
}

public enum PaperFilter {
    public static func apply(
        _ papers: [Paper],
        criteria: PaperFilterCriteria,
        analysesByPaperID: [String: LLMAnalysis] = [:],
        now: Date = Date()
    ) -> [Paper] {
        let search = criteria.searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var selectedTags = Set(criteria.tags.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }.filter { !$0.isEmpty })
        if let tag = criteria.tag?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           !tag.isEmpty {
            selectedTags.insert(tag)
        }

        let filtered = papers.filter { paper in
            if !search.isEmpty, !matchesSearch(paper, search: search) {
                return false
            }
            if let status = criteria.status, paper.status != status {
                return false
            }
            if !selectedTags.isEmpty {
                let paperTags = Set(paper.tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
                if paperTags.isDisjoint(with: selectedTags) {
                    return false
                }
            }
            return criteria.dateRange.contains(paper.updatedAt ?? paper.publishedAt, now: now)
        }
        return sort(filtered, by: criteria.sort, analysesByPaperID: analysesByPaperID)
    }

    private static func matchesSearch(_ paper: Paper, search: String) -> Bool {
        let haystack = [
            paper.title,
            paper.abstract,
            paper.arxivID,
            paper.primaryCategory ?? "",
            paper.authors.joined(separator: " "),
            paper.tags.joined(separator: " ")
        ]
        .joined(separator: " ")
        .lowercased()
        return haystack.contains(search)
    }

    private static func sort(_ papers: [Paper], by option: PaperSortOption, analysesByPaperID: [String: LLMAnalysis]) -> [Paper] {
        papers.sorted { lhs, rhs in
            switch option {
            case .dateDescending:
                return compareDates(lhs, rhs)
            case .relevanceScoreDescending:
                let lhsScore = RelevanceScore.normalized(analysesByPaperID[lhs.arxivID]?.relevanceScore)
                let rhsScore = RelevanceScore.normalized(analysesByPaperID[rhs.arxivID]?.relevanceScore)
                if lhsScore != rhsScore {
                    return lhsScore > rhsScore
                }
                return compareDates(lhs, rhs)
            }
        }
    }

    private static func compareDates(_ lhs: Paper, _ rhs: Paper) -> Bool {
        let lhsDate = lhs.updatedAt ?? lhs.publishedAt ?? .distantPast
        let rhsDate = rhs.updatedAt ?? rhs.publishedAt ?? .distantPast
        if lhsDate != rhsDate {
            return lhsDate > rhsDate
        }
        return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }
}
