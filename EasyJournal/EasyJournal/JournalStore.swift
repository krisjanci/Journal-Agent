import Foundation
import SQLite3

struct JournalEntry: Identifiable, Codable, Equatable {
    var id: String = UUID().uuidString
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var title: String = ""
    var text: String = ""
    var source: String = "manual"
    var duration: Double = 0
    var audioFiles: [String]? = nil
    var analysis: JournalAnalysis? = nil
    var currentAnalysis: JournalAnalysis? { analysis.flatMap { $0.isCurrent(for: text) ? $0 : nil } }
    var summaryTitle: String { title.isEmpty ? (currentAnalysis?.title ?? "Summary pending") : title }
    var summaryPreview: String { currentAnalysis?.summary ?? "Saved safely. A local AI summary will appear here when ready." }
    var wordCount: Int { text.split { $0.isWhitespace || $0.isNewline }.count }
    var displayTitle: String {
        if !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return title }
        let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? "Untitled entry"
        return firstLine.count > 65 ? String(firstLine.prefix(65)) + "…" : firstLine
    }
}

struct JournalFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// SQLite is authoritative. CSV is a replaceable, spreadsheet-safe snapshot.
final class JournalStore {
    let directory: URL
    var csvURL: URL { directory.appendingPathComponent("journal.csv") }
    private var db: OpaquePointer?
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(directory: URL? = nil) throws {
        self.directory = try directory ?? FileManager.default.url(for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("Journal Agent", isDirectory: true)
        try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
        let path = self.directory.appendingPathComponent("journal.sqlite").path
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            let message = errorMessage
            sqlite3_close(db); db = nil
            throw JournalFailure(message: message)
        }
        sqlite3_busy_timeout(db, 5000)
        do {
            try execute("PRAGMA foreign_keys=ON")
            try execute("PRAGMA journal_mode=WAL")
            try execute("PRAGMA synchronous=FULL")
            try execute("CREATE TABLE IF NOT EXISTS entries (id TEXT PRIMARY KEY, created_at REAL NOT NULL, updated_at REAL NOT NULL, title TEXT NOT NULL, text TEXT NOT NULL, source TEXT NOT NULL, duration_seconds REAL NOT NULL)")
            try execute("CREATE TABLE IF NOT EXISTS draft (singleton INTEGER PRIMARY KEY CHECK(singleton=1), payload BLOB NOT NULL)")
            let versionStatement = try prepare("PRAGMA user_version")
            let versionResult = sqlite3_step(versionStatement)
            let version = sqlite3_column_int(versionStatement, 0)
            sqlite3_finalize(versionStatement)
            guard versionResult == SQLITE_ROW, version <= 2 else {
                throw JournalFailure(message: "This journal was created by a newer app version. Open it with the latest Journal Agent.")
            }
            if version < 2 {
                try execute("BEGIN IMMEDIATE")
                do {
                    try execute("ALTER TABLE entries ADD COLUMN audio_files TEXT NOT NULL DEFAULT '[]'")
                    try execute("CREATE TABLE IF NOT EXISTS entry_analysis (entry_id TEXT PRIMARY KEY REFERENCES entries(id) ON DELETE CASCADE, payload BLOB NOT NULL)")
                    try execute("PRAGMA user_version=2")
                    try execute("COMMIT")
                } catch { try? execute("ROLLBACK"); throw error }
            }
        } catch {
            sqlite3_close(db); db = nil
            throw error
        }
    }
    deinit { sqlite3_close(db) }
    private var errorMessage: String { db.map { String(cString: sqlite3_errmsg($0)) } ?? "Unable to open the journal database." }
    private func execute(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw JournalFailure(message: errorMessage) }
    }
    private func prepare(_ sql: String) throws -> OpaquePointer {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { throw JournalFailure(message: errorMessage) }
        return stmt
    }
    private func bind(_ value: String, to stmt: OpaquePointer, at index: Int32) {
        sqlite3_bind_text(stmt, index, value, -1, transient)
    }
    private func run(_ stmt: OpaquePointer) throws {
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw JournalFailure(message: errorMessage) }
    }
    func entries() throws -> [JournalEntry] {
        let stmt = try prepare("SELECT e.id, e.created_at, e.updated_at, e.title, e.text, e.source, e.duration_seconds, e.audio_files, a.payload FROM entries e LEFT JOIN entry_analysis a ON a.entry_id=e.id ORDER BY e.created_at DESC, e.id")
        defer { sqlite3_finalize(stmt) }
        var result: [JournalEntry] = []
        var status = sqlite3_step(stmt)
        func string(_ column: Int32) -> String { String(cString: sqlite3_column_text(stmt, column)) }
        while status == SQLITE_ROW {
            result.append(JournalEntry(id: string(0), createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 1)),
                updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 2)), title: string(3), text: string(4),
                source: string(5), duration: sqlite3_column_double(stmt, 6),
                audioFiles: try JSONDecoder().decode([String].self, from: Data(string(7).utf8))))
            if let bytes = sqlite3_column_blob(stmt, 8) {
                let payload = Data(bytes: bytes, count: Int(sqlite3_column_bytes(stmt, 8)))
                // An unusable derived summary must never make original entries unreadable.
                result[result.count - 1].analysis = try? JSONDecoder().decode(JournalAnalysis.self, from: payload)
            }
            status = sqlite3_step(stmt)
        }
        guard status == SQLITE_DONE else { throw JournalFailure(message: errorMessage) }
        return result
    }
    func save(_ entry: JournalEntry, clearingDraft: Bool = false) throws {
        guard !entry.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !(entry.audioFiles ?? []).isEmpty else { throw JournalFailure(message: "Add a few words before saving.") }
        try execute("BEGIN IMMEDIATE")
        do {
            let stmt = try prepare("INSERT INTO entries (id, created_at, updated_at, title, text, source, duration_seconds, audio_files) VALUES (?, ?, ?, ?, ?, ?, ?, ?) ON CONFLICT(id) DO UPDATE SET updated_at=excluded.updated_at, title=excluded.title, text=excluded.text, source=excluded.source, duration_seconds=excluded.duration_seconds, audio_files=excluded.audio_files")
            defer { sqlite3_finalize(stmt) }
            bind(entry.id, to: stmt, at: 1)
            sqlite3_bind_double(stmt, 2, entry.createdAt.timeIntervalSince1970)
            sqlite3_bind_double(stmt, 3, entry.updatedAt.timeIntervalSince1970)
            bind(entry.title, to: stmt, at: 4); bind(entry.text, to: stmt, at: 5); bind(entry.source, to: stmt, at: 6)
            sqlite3_bind_double(stmt, 7, entry.duration)
            bind(String(decoding: try JSONEncoder().encode(entry.audioFiles ?? []), as: UTF8.self), to: stmt, at: 8)
            try run(stmt)
            if clearingDraft { try execute("DELETE FROM draft") }
            try execute("COMMIT")
        } catch { try? execute("ROLLBACK"); throw error }
    }
    func delete(_ id: String) throws {
        let stmt = try prepare("DELETE FROM entries WHERE id=?")
        defer { sqlite3_finalize(stmt) }
        bind(id, to: stmt, at: 1); try run(stmt)
    }
    func saveAnalysis(_ analysis: JournalAnalysis, for id: String) throws {
        // Check the transcript inside the write transaction so stale work cannot replace newer edits.
        try execute("BEGIN IMMEDIATE")
        do {
            let current = try prepare("SELECT text FROM entries WHERE id=?")
            defer { sqlite3_finalize(current) }
            bind(id, to: current, at: 1)
            guard sqlite3_step(current) == SQLITE_ROW,
                  analysis.isCurrent(for: String(cString: sqlite3_column_text(current, 0))) else {
                throw JournalFailure(message: "The entry changed while it was being summarized. Please try again.")
            }
            let data = try JSONEncoder().encode(analysis)
            let stmt = try prepare("INSERT INTO entry_analysis VALUES (?, ?) ON CONFLICT(entry_id) DO UPDATE SET payload=excluded.payload")
            defer { sqlite3_finalize(stmt) }
            bind(id, to: stmt, at: 1)
            _ = data.withUnsafeBytes { sqlite3_bind_blob(stmt, 2, $0.baseAddress, Int32(data.count), transient) }
            try run(stmt)
            try execute("COMMIT")
        } catch { try? execute("ROLLBACK"); throw error }
    }
    var audioDirectory: URL { directory.appendingPathComponent("Recordings", isDirectory: true) }
    func newRecordingURL() throws -> URL {
        try FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
        return audioDirectory.appendingPathComponent(UUID().uuidString + ".caf")
    }
    func recordingURL(_ name: String) -> URL? {
        guard name == URL(fileURLWithPath: name).lastPathComponent, name.hasSuffix(".caf") else { return nil }
        return audioDirectory.appendingPathComponent(name)
    }
    func saveDraft(_ entry: JournalEntry) throws {
        let data = try JSONEncoder().encode(entry)
        let stmt = try prepare("INSERT INTO draft VALUES (1, ?) ON CONFLICT(singleton) DO UPDATE SET payload=excluded.payload")
        defer { sqlite3_finalize(stmt) }
        _ = data.withUnsafeBytes { sqlite3_bind_blob(stmt, 1, $0.baseAddress, Int32(data.count), transient) }
        try run(stmt)
    }
    func draft() throws -> JournalEntry? {
        let stmt = try prepare("SELECT payload FROM draft WHERE singleton=1")
        defer { sqlite3_finalize(stmt) }
        let status = sqlite3_step(stmt)
        if status == SQLITE_DONE { return nil }
        guard status == SQLITE_ROW, let bytes = sqlite3_column_blob(stmt, 0) else { throw JournalFailure(message: errorMessage) }
        return try JSONDecoder().decode(JournalEntry.self, from: Data(bytes: bytes, count: Int(sqlite3_column_bytes(stmt, 0))))
    }
    func clearDraft() throws { try execute("DELETE FROM draft") }
    func writeCSV(to url: URL? = nil) throws {
        try Self.csv(entries: entries()).write(to: url ?? csvURL, atomically: true, encoding: .utf8)
    }
    static func csv(entries: [JournalEntry]) -> String {
        let formatter = ISO8601DateFormatter()
        func quote(_ text: String) -> String {
            // Keep spreadsheet applications from executing a journal sentence as a formula.
            let leading = text.drop(while: { $0.isWhitespace }).first
            let safe = leading.map { "=+-@".contains($0) } == true ? "'" + text : text
            return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        let header = "id,created_at,updated_at,title,text,source,duration_seconds,word_count,summary,topics,activities,accomplishments,next_steps,feelings,analysis_generated_at,analysis_engine,analysis_system_version,analysis_version,analysis_source_hash,audio_files\r\n"
        func json<T: Encodable>(_ value: T) -> String { (try? String(decoding: JSONEncoder().encode(value), as: UTF8.self)) ?? "[]" }
        return header + entries.map { entry in
            let analysis = entry.currentAnalysis
            return [entry.id, formatter.string(from: entry.createdAt), formatter.string(from: entry.updatedAt), entry.displayTitle,
             entry.text, entry.source, String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), entry.duration), String(entry.wordCount),
             analysis?.summary ?? "", json(analysis?.topics ?? []), json(analysis?.activities ?? []),
             json(analysis?.accomplishments ?? []), json(analysis?.nextSteps ?? []), json(analysis?.feelings ?? []),
             analysis.map { formatter.string(from: $0.generatedAt) } ?? "", analysis?.engine ?? "", analysis?.systemVersion ?? "",
             analysis.map { String($0.version) } ?? "", analysis?.sourceHash ?? "", json(entry.audioFiles ?? [])]
                .map(quote).joined(separator: ",")
        }.joined(separator: "\r\n") + (entries.isEmpty ? "" : "\r\n")
    }
}
