import Foundation
import SQLite3

@main struct AnalysisStorageTests {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("JournalMigration-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var db: OpaquePointer?
        sqlite3_open(directory.appendingPathComponent("journal.sqlite").path, &db)
        let sql = """
        CREATE TABLE entries(id TEXT PRIMARY KEY, created_at REAL NOT NULL, updated_at REAL NOT NULL, title TEXT NOT NULL, text TEXT NOT NULL, source TEXT NOT NULL, duration_seconds REAL NOT NULL);
        CREATE TABLE draft(singleton INTEGER PRIMARY KEY, payload BLOB NOT NULL);
        INSERT INTO entries VALUES ('legacy', 1800000000, 1800000000, '', 'I felt proud after finishing my project.', 'voice', 12);
        PRAGMA user_version=1;
        """
        precondition(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK)
        sqlite3_close(db)
        let store = try JournalStore(directory: directory)
        var entry = try store.entries().first!
        precondition(entry.id == "legacy" && entry.audioFiles == [])
        let analysis = JournalAnalysis(title: "Finished a project", summary: "Completed a project and felt proud.", topics: ["project"], activities: ["project work"], accomplishments: ["Finished project"], nextSteps: [], feelings: [FeelingEvidence(feeling: "proud", quote: "felt proud")], sourceHash: JournalAnalysis.hash(entry.text))
        try store.saveAnalysis(analysis, for: entry.id)
        let analyzed = try store.entries().first!
        precondition(analyzed.currentAnalysis?.summary == analysis.summary)
        precondition(JournalStore.csv(entries: [analyzed]).contains(analysis.summary))
        entry.text = "I went for a walk."
        try store.save(entry)
        let changed = try store.entries().first!
        precondition(changed.currentAnalysis == nil)
        precondition(!JournalStore.csv(entries: [changed]).contains(analysis.summary))
        do { try store.saveAnalysis(analysis, for: entry.id); fatalError("Stale analysis must be rejected") }
        catch is JournalFailure {}
        let recording = try store.newRecordingURL()
        entry.audioFiles = [recording.lastPathComponent]; entry.text = ""
        try store.save(entry)
        let audioOnly = try store.entries().first!
        precondition(audioOnly.audioFiles == entry.audioFiles)
        precondition(store.recordingURL("../outside.caf") == nil)
        let longText = String(repeating: "A long journal passage. 日本語 🌿\n", count: 500)
        let chunks = JournalText.chunks(longText)
        precondition(chunks.joined() == longText && chunks.allSatisfy { $0.count <= 2800 })
        try store.delete(entry.id)
        let remaining = try store.entries()
        precondition(remaining.isEmpty)
        print("PASS: v1 migration, analysis persistence, stale-result protection, CSV metadata, audio metadata, lossless chunking")
    }
}
