import Foundation
import SQLite3

public final class SQLiteResearchStore {
    private var db: OpaquePointer?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(path: URL) throws {
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        if sqlite3_open(path.path, &db) != SQLITE_OK {
            throw SQLiteStoreError.openFailed(lastError)
        }
        try executePragma("PRAGMA busy_timeout = 5000;")
        try executePragma("PRAGMA journal_mode = WAL;")
        try migrate()
    }

    deinit {
        sqlite3_close(db)
    }

    public func migrate() throws {
        try execute("""
        CREATE TABLE IF NOT EXISTS query_profiles (
            id TEXT PRIMARY KEY,
            json TEXT NOT NULL
        );
        """)
        try execute("""
        CREATE TABLE IF NOT EXISTS papers (
            arxiv_id TEXT PRIMARY KEY,
            json TEXT NOT NULL,
            updated_at TEXT
        );
        """)
        try execute("""
        CREATE TABLE IF NOT EXISTS analyses (
            id TEXT PRIMARY KEY,
            paper_id TEXT NOT NULL,
            json TEXT NOT NULL,
            created_at TEXT NOT NULL
        );
        """)
        try execute("""
        CREATE TABLE IF NOT EXISTS jobs (
            id TEXT PRIMARY KEY,
            kind TEXT NOT NULL,
            state TEXT NOT NULL,
            json TEXT NOT NULL,
            scheduled_at REAL NOT NULL
        );
        """)
        try execute("""
        CREATE TABLE IF NOT EXISTS canonical_tags (
            id TEXT PRIMARY KEY,
            name TEXT UNIQUE NOT NULL,
            json TEXT NOT NULL
        );
        """)
        try execute("""
        CREATE TABLE IF NOT EXISTS deep_reads (
            id TEXT PRIMARY KEY,
            paper_id TEXT NOT NULL,
            json TEXT NOT NULL,
            created_at TEXT NOT NULL
        );
        """)
    }

    public func upsertQueryProfile(_ profile: QueryProfile) throws {
        try upsert(table: "query_profiles", keyColumn: "id", key: profile.id.uuidString, json: profile)
    }

    public func fetchQueryProfiles() throws -> [QueryProfile] {
        try fetchJSON("SELECT json FROM query_profiles ORDER BY json")
    }

    public func deleteQueryProfile(id: UUID) throws {
        try deleteQueryProfile(id: id, deleteAssociatedPapers: false)
    }

    public func deleteQueryProfile(id: UUID, deleteAssociatedPapers: Bool) throws {
        for paper in try fetchPapers() where paper.queryProfileIDs.contains(id) {
            let remainingQueryIDs = paper.queryProfileIDs.filter { $0 != id }
            if deleteAssociatedPapers && remainingQueryIDs.isEmpty {
                try deletePaper(arxivID: paper.arxivID)
            } else {
                var retainedPaper = paper
                retainedPaper.queryProfileIDs = remainingQueryIDs
                try upsertPaper(retainedPaper)
            }
        }
        try execute("DELETE FROM query_profiles WHERE id = ?", [.string(id.uuidString)])
    }

    public func upsertPaper(_ paper: Paper) throws {
        let data = try encoder.encode(paper)
        let json = String(decoding: data, as: UTF8.self)
        try execute(
            "INSERT OR REPLACE INTO papers (arxiv_id, json, updated_at) VALUES (?, ?, ?)",
            [.string(paper.arxivID), .string(json), .string(paper.updatedAt.map { ISO8601DateFormatter().string(from: $0) } ?? "")]
        )
    }

    public func fetchPapers() throws -> [Paper] {
        try fetchJSON("SELECT json FROM papers ORDER BY updated_at DESC, arxiv_id DESC")
    }

    public func fetchPaper(arxivID: String) throws -> Paper? {
        let rows: [Paper] = try fetchJSON("SELECT json FROM papers WHERE arxiv_id = ? LIMIT 1", [.string(arxivID)])
        return rows.first
    }

    public func deletePaper(arxivID: String) throws {
        try execute("DELETE FROM papers WHERE arxiv_id = ?", [.string(arxivID)])
        try execute("DELETE FROM analyses WHERE paper_id = ?", [.string(arxivID)])
        try execute("DELETE FROM deep_reads WHERE paper_id = ?", [.string(arxivID)])
        for job in try fetchJobs() where String(data: job.payload, encoding: .utf8) == arxivID {
            try deleteJob(id: job.id)
        }
    }

    public func saveAnalysis(_ analysis: LLMAnalysis) throws {
        let data = try encoder.encode(analysis)
        try execute(
            "INSERT OR REPLACE INTO analyses (id, paper_id, json, created_at) VALUES (?, ?, ?, ?)",
            [
                .string(analysis.id.uuidString),
                .string(analysis.paperID),
                .string(String(decoding: data, as: UTF8.self)),
                .string(ISO8601DateFormatter().string(from: analysis.createdAt))
            ]
        )
    }

    public func latestAnalysis(for paperID: String) throws -> LLMAnalysis? {
        let rows: [LLMAnalysis] = try fetchJSON("SELECT json FROM analyses WHERE paper_id = ? ORDER BY created_at DESC LIMIT 1", [.string(paperID)])
        return rows.first
    }

    public func saveDeepRead(_ report: DeepReadReport) throws {
        let data = try encoder.encode(report)
        try execute(
            "INSERT OR REPLACE INTO deep_reads (id, paper_id, json, created_at) VALUES (?, ?, ?, ?)",
            [
                .string(report.id.uuidString),
                .string(report.paperID),
                .string(String(decoding: data, as: UTF8.self)),
                .string(ISO8601DateFormatter().string(from: report.createdAt))
            ]
        )
    }

    public func latestDeepRead(for paperID: String) throws -> DeepReadReport? {
        let rows: [DeepReadReport] = try fetchJSON("SELECT json FROM deep_reads WHERE paper_id = ? ORDER BY created_at DESC LIMIT 1", [.string(paperID)])
        return rows.first
    }

    public func enqueue(_ job: SyncJob) throws {
        let data = try encoder.encode(job)
        try execute(
            "INSERT OR REPLACE INTO jobs (id, kind, state, json, scheduled_at) VALUES (?, ?, ?, ?, ?)",
            [
                .string(job.id.uuidString),
                .string(job.kind.rawValue),
                .string(job.state.rawValue),
                .string(String(decoding: data, as: UTF8.self)),
                .double(job.scheduledAt.timeIntervalSince1970)
            ]
        )
    }

    public func nextPendingJob(now: Date = Date()) throws -> SyncJob? {
        let rows: [SyncJob] = try fetchJSON(
            "SELECT json FROM jobs WHERE state = ? AND scheduled_at <= ? ORDER BY scheduled_at ASC LIMIT 1",
            [.string(SyncJob.State.pending.rawValue), .double(now.timeIntervalSince1970)]
        )
        return rows.first
    }

    public func fetchJob(id: UUID) throws -> SyncJob? {
        let rows: [SyncJob] = try fetchJSON("SELECT json FROM jobs WHERE id = ? LIMIT 1", [.string(id.uuidString)])
        return rows.first
    }

    public func fetchJobs(kind: SyncJob.Kind? = nil, state: SyncJob.State? = nil, limit: Int = 100) throws -> [SyncJob] {
        if let kind, let state {
            return try fetchJSON(
                "SELECT json FROM jobs WHERE kind = ? AND state = ? ORDER BY scheduled_at ASC LIMIT ?",
                [.string(kind.rawValue), .string(state.rawValue), .int(limit)]
            )
        }
        if let kind {
            return try fetchJSON(
                "SELECT json FROM jobs WHERE kind = ? ORDER BY scheduled_at DESC LIMIT ?",
                [.string(kind.rawValue), .int(limit)]
            )
        }
        if let state {
            return try fetchJSON(
                "SELECT json FROM jobs WHERE state = ? ORDER BY scheduled_at ASC LIMIT ?",
                [.string(state.rawValue), .int(limit)]
            )
        }
        return try fetchJSON(
            "SELECT json FROM jobs ORDER BY scheduled_at DESC LIMIT ?",
            [.int(limit)]
        )
    }

    public func countJobs(kind: SyncJob.Kind? = nil, state: SyncJob.State? = nil) throws -> Int {
        if let kind, let state {
            return try fetchInt(
                "SELECT COUNT(*) FROM jobs WHERE kind = ? AND state = ?",
                [.string(kind.rawValue), .string(state.rawValue)]
            )
        }
        if let kind {
            return try fetchInt("SELECT COUNT(*) FROM jobs WHERE kind = ?", [.string(kind.rawValue)])
        }
        if let state {
            return try fetchInt("SELECT COUNT(*) FROM jobs WHERE state = ?", [.string(state.rawValue)])
        }
        return try fetchInt("SELECT COUNT(*) FROM jobs")
    }

    public func claimJob(id: UUID, allowedStates: Set<SyncJob.State> = [.pending]) throws -> SyncJob? {
        try claimJob(id: id, allowedStates: allowedStates, deviceID: nil)
    }

    public func claimJob(
        id: UUID,
        deviceID: String?,
        now: Date = Date(),
        allowedStates: Set<SyncJob.State> = [.pending]
    ) throws -> SyncJob? {
        try claimJob(id: id, allowedStates: allowedStates, deviceID: deviceID, now: now)
    }

    private func claimJob(
        id: UUID,
        allowedStates: Set<SyncJob.State>,
        deviceID: String?,
        now: Date = Date()
    ) throws -> SyncJob? {
        guard var job = try fetchJob(id: id), allowedStates.contains(job.state) else {
            return nil
        }
        job.state = .running
        job.lastError = nil
        job.claimedByDeviceID = deviceID
        job.claimedAt = Self.persistableDate(now)
        job.completedAt = nil
        let data = try encoder.encode(job)
        let allowed = allowedStates.map(\.rawValue)
        let placeholders = Array(repeating: "?", count: allowed.count).joined(separator: ",")
        let changes = try executeReturningChanges(
            "UPDATE jobs SET state = ?, json = ? WHERE id = ? AND state IN (\(placeholders))",
            [.string(SyncJob.State.running.rawValue), .string(String(decoding: data, as: UTF8.self)), .string(id.uuidString)] + allowed.map { .string($0) }
        )
        return changes > 0 ? job : nil
    }

    public func deleteJob(id: UUID) throws {
        try execute("DELETE FROM jobs WHERE id = ?", [.string(id.uuidString)])
    }

    @discardableResult
    public func deleteJobs(kind: SyncJob.Kind? = nil, state: SyncJob.State? = nil, includingRunning: Bool = false) throws -> Int {
        var clauses: [String] = []
        var values: [SQLiteValue] = []
        if let kind {
            clauses.append("kind = ?")
            values.append(.string(kind.rawValue))
        }
        if let state {
            clauses.append("state = ?")
            values.append(.string(state.rawValue))
        } else if !includingRunning {
            clauses.append("state != ?")
            values.append(.string(SyncJob.State.running.rawValue))
        }
        let whereClause = clauses.isEmpty ? "" : " WHERE \(clauses.joined(separator: " AND "))"
        return try executeReturningChanges("DELETE FROM jobs\(whereClause)", values)
    }

    public func markJob(_ jobID: UUID, state: SyncJob.State, error: String? = nil) throws {
        let rows: [SyncJob] = try fetchJSON("SELECT json FROM jobs WHERE id = ? LIMIT 1", [.string(jobID.uuidString)])
        guard var job = rows.first else { return }
        job.state = state
        job.lastError = error
        job.attempts += state == .failed ? 1 : 0
        switch state {
        case .succeeded, .failed:
            job.completedAt = Self.persistableDate(Date())
        case .pending:
            job.claimedAt = nil
            job.claimedByDeviceID = nil
            job.completedAt = nil
        case .running:
            job.completedAt = nil
        }
        try enqueue(job)
    }

    public func saveCanonicalTags(_ tags: [CanonicalTag]) throws {
        for tag in tags {
            try upsert(table: "canonical_tags", keyColumn: "id", key: tag.id.uuidString, json: tag, uniqueName: tag.name)
        }
    }

    public func fetchCanonicalTags() throws -> [CanonicalTag] {
        try fetchJSON("SELECT json FROM canonical_tags ORDER BY name")
    }

    private static func persistableDate(_ date: Date) -> Date {
        Date(timeIntervalSince1970: floor(date.timeIntervalSince1970))
    }

    private func upsert<T: Encodable>(table: String, keyColumn: String, key: String, json value: T, uniqueName: String? = nil) throws {
        let data = try encoder.encode(value)
        if let uniqueName {
            try execute(
                "INSERT OR REPLACE INTO \(table) (\(keyColumn), name, json) VALUES (?, ?, ?)",
                [.string(key), .string(uniqueName), .string(String(decoding: data, as: UTF8.self))]
            )
        } else {
            try execute(
                "INSERT OR REPLACE INTO \(table) (\(keyColumn), json) VALUES (?, ?)",
                [.string(key), .string(String(decoding: data, as: UTF8.self))]
            )
        }
    }

    private func fetchJSON<T: Decodable>(_ sql: String, _ values: [SQLiteValue] = []) throws -> [T] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteStoreError.prepareFailed(lastError)
        }
        defer { sqlite3_finalize(statement) }
        try bind(values, to: statement)

        var rows: [T] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let cString = sqlite3_column_text(statement, 0) else { continue }
            let json = String(cString: cString)
            let data = Data(json.utf8)
            rows.append(try decoder.decode(T.self, from: data))
        }
        return rows
    }

    private func fetchInt(_ sql: String, _ values: [SQLiteValue] = []) throws -> Int {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteStoreError.prepareFailed(lastError)
        }
        defer { sqlite3_finalize(statement) }
        try bind(values, to: statement)
        guard sqlite3_step(statement) == SQLITE_ROW else {
            return 0
        }
        return Int(sqlite3_column_int(statement, 0))
    }

    private func executePragma(_ sql: String) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteStoreError.prepareFailed(lastError)
        }
        defer { sqlite3_finalize(statement) }
        let result = sqlite3_step(statement)
        guard result == SQLITE_DONE || result == SQLITE_ROW else {
            throw SQLiteStoreError.executeFailed(lastError)
        }
    }

    private func execute(_ sql: String, _ values: [SQLiteValue] = []) throws {
        _ = try executeReturningChanges(sql, values)
    }

    private func executeReturningChanges(_ sql: String, _ values: [SQLiteValue] = []) throws -> Int {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteStoreError.prepareFailed(lastError)
        }
        defer { sqlite3_finalize(statement) }
        try bind(values, to: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SQLiteStoreError.executeFailed(lastError)
        }
        return Int(sqlite3_changes(db))
    }

    private func bind(_ values: [SQLiteValue], to statement: OpaquePointer?) throws {
        for (index, value) in values.enumerated() {
            let sqliteIndex = Int32(index + 1)
            switch value {
            case let .string(value):
                sqlite3_bind_text(statement, sqliteIndex, value, -1, SQLITE_TRANSIENT)
            case let .double(value):
                sqlite3_bind_double(statement, sqliteIndex, value)
            case let .int(value):
                sqlite3_bind_int64(statement, sqliteIndex, Int64(value))
            case .null:
                sqlite3_bind_null(statement, sqliteIndex)
            }
        }
    }

    private var lastError: String {
        if let db, let message = sqlite3_errmsg(db) {
            return String(cString: message)
        }
        return "unknown SQLite error"
    }
}

public enum SQLiteValue {
    case string(String)
    case double(Double)
    case int(Int)
    case null
}

public enum SQLiteStoreError: Error, LocalizedError {
    case openFailed(String)
    case prepareFailed(String)
    case executeFailed(String)

    public var errorDescription: String? {
        switch self {
        case let .openFailed(message):
            "SQLite open failed: \(message)"
        case let .prepareFailed(message):
            "SQLite prepare failed: \(message)"
        case let .executeFailed(message):
            "SQLite execute failed: \(message)"
        }
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

extension SQLiteValue: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
    public init(integerLiteral value: Int) { self = .int(value) }
    public init(floatLiteral value: Double) { self = .double(value) }
}
