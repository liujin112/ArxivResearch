import Foundation

public enum PaperDateRange: String, CaseIterable, Codable, Hashable, Sendable {
    case all
    case today
    case yesterday
    case thisWeek
    case last7Days
    case last30Days
    case lastYear

    public var displayName: String {
        switch self {
        case .all:
            "All dates"
        case .today:
            "Today"
        case .yesterday:
            "Yesterday"
        case .thisWeek:
            "This Week"
        case .last7Days:
            "Last 7 days"
        case .last30Days:
            "Last 30 days"
        case .lastYear:
            "Last year"
        }
    }

    func contains(_ date: Date?, now: Date, calendar: Calendar) -> Bool {
        guard self != .all else { return true }
        guard let date else { return false }
        switch self {
        case .all:
            return true
        case .today:
            return calendar.isDate(date, inSameDayAs: now)
        case .yesterday:
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: now) else {
                return false
            }
            return calendar.isDate(date, inSameDayAs: yesterday)
        case .thisWeek:
            guard let interval = calendar.dateInterval(of: .weekOfYear, for: now) else {
                return false
            }
            return date >= interval.start && date < interval.end
        case .last7Days:
            return date >= now.addingTimeInterval(-7 * 86_400)
        case .last30Days:
            return date >= now.addingTimeInterval(-30 * 86_400)
        case .lastYear:
            return date >= now.addingTimeInterval(-365 * 86_400)
        }
    }
}

public enum PaperDateField: String, CaseIterable, Codable, Hashable, Sendable {
    case added
    case published
    case updated

    public var displayName: String {
        switch self {
        case .added:
            "Added"
        case .published:
            "Published"
        case .updated:
            "Updated"
        }
    }

    func date(in paper: Paper) -> Date? {
        switch self {
        case .added:
            paper.addedAt
        case .published:
            paper.publishedAt
        case .updated:
            paper.updatedAt
        }
    }
}

public struct PaperFilterCriteria: Codable, Hashable, Sendable {
    public var searchText: String
    public var status: PaperStatus?
    public var tag: String?
    public var tags: Set<String>
    public var dateRange: PaperDateRange
    public var dateField: PaperDateField
    public var sort: PaperSortOption
    public var queryProfileID: UUID?
    public var libraryDate: PaperLibraryDateFilter

    public init(
        searchText: String = "",
        status: PaperStatus? = nil,
        tag: String? = nil,
        tags: Set<String> = [],
        dateRange: PaperDateRange = .all,
        dateField: PaperDateField = .published,
        sort: PaperSortOption = .dateDescending,
        queryProfileID: UUID? = nil,
        libraryDate: PaperLibraryDateFilter = .all
    ) {
        self.searchText = searchText
        self.status = status
        self.tag = tag
        self.tags = tags
        self.dateRange = dateRange
        self.dateField = dateField
        self.sort = sort
        self.queryProfileID = queryProfileID
        self.libraryDate = libraryDate
    }
}

public enum PaperLibraryDateFilter: Codable, Hashable, Sendable {
    case all
    case day(field: PaperDateField, date: Date)
    case thisWeek(field: PaperDateField, referenceDate: Date)

    func contains(_ paper: Paper, calendar: Calendar) -> Bool {
        switch self {
        case .all:
            return true
        case let .day(field, day):
            guard let date = field.date(in: paper) else {
                return false
            }
            return calendar.isDate(date, inSameDayAs: day)
        case let .thisWeek(field, referenceDate):
            guard let date = field.date(in: paper),
                  let interval = calendar.dateInterval(of: .weekOfYear, for: referenceDate)
            else {
                return false
            }
            return date >= interval.start && date < interval.end
        }
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
        field: PaperDateField,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [PaperLibraryDateBucket] {
        let dates = papers.compactMap { paper -> Date? in
            guard let date = field.date(in: paper) else {
                return nil
            }
            return calendar.startOfDay(for: date)
        }
        let groupedDates = Dictionary(grouping: dates) { $0 }

        return groupedDates
            .map { date, dates in
                PaperLibraryDateBucket(
                    title: dateTitle(for: date, calendar: calendar),
                    count: dates.count,
                    filter: .day(field: field, date: date)
                )
            }
            .sorted { lhs, rhs in
                date(for: lhs) > date(for: rhs)
            }
    }

    public static func thisWeekBucket(
        for papers: [Paper],
        field: PaperDateField,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> PaperLibraryDateBucket {
        let referenceDate = calendar.startOfDay(for: now)
        let filter = PaperLibraryDateFilter.thisWeek(field: field, referenceDate: referenceDate)
        let count = papers.filter { filter.contains($0, calendar: calendar) }.count
        return PaperLibraryDateBucket(title: "This Week", count: count, filter: filter)
    }

    private static func date(for bucket: PaperLibraryDateBucket) -> Date {
        if case let .day(_, date) = bucket.filter {
            return date
        }
        return .distantPast
    }

    private static func dateTitle(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
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
            return criteria.dateRange.contains(criteria.dateField.date(in: paper), now: now, calendar: calendar)
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
