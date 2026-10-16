import Foundation

@main
struct StorageTests {
    static func expect(_ condition: @autoclosure () throws -> Bool, _ message: String = "Assertion failed", line: UInt = #line) throws {
        guard try condition() else { fatalError("Line \(line): \(message)") }
    }
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("JournalAgentTests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        var store: JournalStore? = try JournalStore(directory: directory)
        var entry = JournalEntry(createdAt: Date(timeIntervalSince1970: 1_800_000_000), updatedAt: Date(timeIntervalSince1970: 1_800_000_000), title: "A day, with \"quotes\"", text: "A first line.\nCafé 🌿, \"hello\".", source: "voice", duration: 61.5, audioFiles: [])
        try store!.saveDraft(entry)
        store = nil
        store = try JournalStore(directory: directory)
        let draft = try store!.draft()
        try expect(draft == entry, "Draft must survive reopening the database")
        try store!.save(entry, clearingDraft: true)
        try expect(try store!.draft() == nil)
        try expect(try store!.entries() == [entry])
        entry.text += " More thoughts."; entry.updatedAt = Date()
        try store!.save(entry)
        try expect(try store!.entries().count == 1, "Editing must not create a duplicate")
        try expect(try store!.entries().first?.text == entry.text)
        try store!.writeCSV()
        let csv = try String(contentsOf: store!.csvURL, encoding: .utf8)
        try expect(csv.contains("\"A day, with \"\"quotes\"\"\""))
        try expect(csv.contains("Café 🌿, \"\"hello\"\"."))
        try expect(csv.contains("\"61.5\""))
        for formula in ["=SUM(1,2)", " +1+1", "\t@SUM(A1)", "-1+1"] {
            let safe = JournalStore.csv(entries: [JournalEntry(text: formula)])
            try expect(safe.contains("\"'" + formula + "\""))
        }
        try store!.saveDraft(entry)
        do {
            try store!.save(JournalEntry(text: " \n"), clearingDraft: true)
            fatalError("Blank entries should fail")
        } catch is JournalFailure {}
        try expect(try store!.draft() != nil, "Failed saves must preserve the draft")
        try store!.delete(entry.id)
        try expect(try store!.entries().isEmpty)
        try store!.clearDraft()
        try expect(try store!.draft() == nil)
        try store!.writeCSV()
        try expect(try String(contentsOf: store!.csvURL, encoding: .utf8).split(separator: "\n").count == 1)
        print("PASS: persistence, draft recovery, editing, Unicode/multiline CSV, formula escaping, failed saves, deletion")
    }
}
