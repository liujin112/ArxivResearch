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
    public var queryProfileID: UUID?
    public var libraryDate: PaperLibraryDateFilter

    public init(
        searchText: String = "",
        status: PaperStatus? = nil,
        tag: String? = nil,
        tags: Set<String> = [],
        dateRange: PaperDateRange = .all,
        sort: PaperSortOption = .dateDescending,
        queryProfileID: UUID? = nil,
        libraryDate: PaperLibraryDateFilter = .all
    ) {
        self.searchText = searchText
        self.status = status
        self.tag = tag
        self.tags = tags
        self.dateRange = dateRange
        self.sort = sort
        self.queryProfileID = queryProfileID
        self.libraryDate = libraryDate
    }
}

public enum PaperLibraryDateFilter: Codable, Hashable, Sendable {
    case all
    case day(Date)
    case thisWeek(referenceDate: Date)

    func contains(_ paper: Paper, calendar: Calendar) -> Bool {
        guard let date = paper.localLibraryDate else {
            return self == .all
        }
        switch self {
        case .all:
            return true
        case let .day(day):
            return calendar.isDate(date, inSameDayAs: day)
        case let .thisWeek(referenceDate):
            return Self.isEarlierThisWeek(date, referenceDate: referenceDate, calendar: calendar)
        }
    }

    private static func isEarlierThisWeek(_ date: Date, referenceDate: Date, calendar: Calendar) -> Bool {
        guard calendar.isDate(date, equalTo: referenceDate, toGranularity: .weekOfYear),
              calendar.component(.yearForWeekOfYear, from: date) == calendar.component(.yearForWeekOfYear, from: referenceDate)
        else {
            return false
        }
        if calendar.isDate(date, inSameDayAs: referenceDate) {
            return false
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: referenceDate),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return false
        }
        return date < calendar.startOfDay(for: referenceDate)
    }
}

public struct PaperLibraryDateBucket: Identifiable, Hashable, Sendable {
    public var id: PaperLibraryDateFilter { filter }
    public var title: String
    public var count: Int
    public var filter: PaperLibraryDateFilter

    public init(title: String, count: Int, filter: PaperLibraryDateFilter) {
        self.title = title
        self.count = count
        self.filter = filter
    }
}

public enum PaperLibraryDateBuckets {
    public static func make(
        for papers: [Paper],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [PaperLibraryDateBucket] {
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -1, to: today) ?? today)
        let datedPapers = papers.compactMap { paper -> (paper: Paper, date: Date)? in
            guard let date = paper.localLibraryDate else { return nil }
            return (paper, calendar.startOfDay(for: date))
        }
        var buckets: [PaperLibraryDateBucket] = []

        let todayCount = datedPapers.filter { calendar.isDate($0.date, inSameDayAs: today) }.count
        if todayCount > 0 {
            buckets.append(PaperLibraryDateBucket(title: "Today", count: todayCount, filter: .day(today)))
        }

        let yesterdayCount = datedPapers.filter { calendar.isDate($0.date, inSameDayAs: yesterday) }.count
        if yesterdayCount > 0 {
            buckets.append(PaperLibraryDateBucket(title: "Yesterday", count: yesterdayCount, filter: .day(yesterday)))
        }

        let thisWeekReference = today
        let thisWeekFilter = PaperLibraryDateFilter.thisWeek(referenceDate: thisWeekReference)
        let thisWeekCount = datedPapers.filter {
            thisWeekFilter.contains($0.paper, calendar: calendar)
        }.count
        if thisWeekCount > 0 {
            buckets.append(PaperLibraryDateBucket(title: "This Week", count: thisWeekCount, filter: thisWeekFilter))
        }

        let olderDates = datedPapers
            .filter {
                !calendar.isDate($0.date, inSameDayAs: today)
                    && !calendar.isDate($0.date, inSameDayAs: yesterday)
                    && !thisWeekFilter.contains($0.paper, calendar: calendar)
            }
            .map(\.date)
        let groupedOlderDates = Dictionary(grouping: olderDates) { $0 }

        buckets.append(contentsOf: groupedOlderDates
            .map { date, dates in
                PaperLibraryDateBucket(
                    title: sidebarDateFormatter.string(from: date),
                    count: dates.count,
                    filter: .day(date)
                )
            }
            .sorted { lhs, rhs in
                guard case let .day(lhsDate) = lhs.filter,
                      case let .day(rhsDate) = rhs.filter
                else {
                    return lhs.title < rhs.title
                }
                return lhsDate > rhsDate
            })

        return buckets
    }

    private static let sidebarDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}

private extension Paper {
    var localLibraryDate: Date? {
        addedAt ?? updatedAt ?? publishedAt
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
        now: Date = Date(),
        calendar: Calendar = .current
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
            if let queryProfileID = criteria.queryProfileID,
               !paper.queryProfileIDs.contains(queryProfileID) {
                return false
            }
            if !selectedTags.isEmpty {
                let paperTags = Set(paper.tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
                if paperTags.isDisjoint(with: selectedTags) {
                    return false
                }
            }
            return criteria.dateRange.contains(paper.updatedAt ?? paper.publishedAt, now: now)
                && criteria.libraryDate.contains(paper, calendar: calendar)
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
