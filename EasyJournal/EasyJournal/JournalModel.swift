import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

@MainActor
final class JournalModel: ObservableObject {
    @Published var entries: [JournalEntry] = []
    @Published var draft = JournalEntry()
    @Published var selectedID: String?
    @Published var composing = false
    @Published var error: String?
    @Published var notice: String?
    @Published var ready = false
    @Published var analysisID: String?
    @Published var analysisFailures: [String: String] = [:]
    @Published var aiMessage = JournalIntelligence.availabilityMessage
    @Published var searchQuery = ""
    @Published var searchedQuery = ""
    @Published var searchMatches: [JournalSearchMatch]?
    @Published var searchStatus = ""
    @Published var searching = false
    var recordingInProgress = false
    @Published var searchError: String?
    @Published var keywordFallback = false
    let intelligence = JournalIntelligence()
    var store: JournalStore?
    var analysisTask: Task<Void, Never>?
    var searchTask: Task<Void, Never>?
    var searchToken = UUID()

    init() {
        do {
            var directory: URL? = nil
            #if DEBUG
            // Isolated QA journals never touch the user's actual journal.
            if let index = CommandLine.arguments.firstIndex(of: "--test-journal"), CommandLine.arguments.count > index + 1 {
                let name = URL(fileURLWithPath: CommandLine.arguments[index + 1]).lastPathComponent
                directory = FileManager.default.temporaryDirectory.appendingPathComponent("JournalAgent-QA").appendingPathComponent(name)
            }
            #endif
            let store = try JournalStore(directory: directory)
            self.store = store
            entries = try store.entries()
            draft = try store.draft() ?? JournalEntry()
            ready = true
            composing = entries.isEmpty || hasDraft
            refreshCSV()
        } catch { self.error = "Your journal could not be opened. \(error.localizedDescription)" }
    }
    var selected: JournalEntry? { entries.first { $0.id == selectedID } }
    var hasDraft: Bool { !draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !(draft.audioFiles ?? []).isEmpty }
    var visibleEntries: [JournalEntry] {
        guard let matches = searchMatches else { return entries }
        let lookup = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
        return matches.compactMap { lookup[$0.id] }
    }
    func newEntry() { invalidateSearch(); if !hasDraft { draft = JournalEntry() }; selectedID = nil; composing = true; notice = nil }
    func showLibrary() { selectedID = nil; composing = false }
    func persistDraft() {
        guard let store else { return }
        do { try store.saveDraft(draft) }
        catch { self.error = "Your draft could not be saved. \(error.localizedDescription)" }
    }
    func recordingDestination() throws -> URL {
        guard let store else { throw JournalFailure(message: "The journal storage isn't available.") }
        return try store.newRecordingURL()
    }
    func attachRecording(_ url: URL) {
        draft.audioFiles = (draft.audioFiles ?? []) + [url.lastPathComponent]
        draft.source = draft.text.isEmpty ? "voice" : "mixed"
        persistDraft()
    }
    func audioURL(_ name: String) -> URL? { store?.recordingURL(name) }
    func saveDraft() {
        guard let store, hasDraft else { return }
        var entry = draft
        entry.text = entry.text.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.updatedAt = Date()
        do {
            try store.save(entry, clearingDraft: true)
            entries = try store.entries()
            draft = JournalEntry(); selectedID = entry.id; composing = false
            notice = "Original entry saved."
            invalidateSearch(); refreshCSV(); processPendingAnalysis()
        } catch { self.error = "Couldn't save your entry. Your draft is still here. \(error.localizedDescription)" }
    }
    func update(_ entry: JournalEntry) -> Bool {
        guard let store else { return false }
        do {
            var revised = entry; revised.updatedAt = Date()
            try store.save(revised)
            entries = try store.entries()
            analysisFailures[entry.id] = nil
            notice = "Original updated. Its summary will refresh."
            invalidateSearch(); refreshCSV(); processPendingAnalysis()
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func delete(_ entry: JournalEntry) {
        guard let store else { return }
        do {
            try store.delete(entry.id)
            entries = try store.entries(); selectedID = nil; composing = false
            // Remove audio only after the database operation succeeds.
            for name in entry.audioFiles ?? [] {
                if let url = store.recordingURL(name), FileManager.default.fileExists(atPath: url.path) {
                    do { try FileManager.default.removeItem(at: url) }
                    catch { self.error = "Entry deleted, but a recording could not be removed: \(error.localizedDescription)" }
                }
            }
            analysisFailures[entry.id] = nil
            invalidateSearch(); refreshCSV()
        } catch { self.error = error.localizedDescription }
    }
    func discardDraft() {
        do {
            let recordings = draft.audioFiles ?? []
            try store?.clearDraft(); draft = JournalEntry()
            for name in recordings {
                if let url = store?.recordingURL(name), FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            }
        } catch { self.error = error.localizedDescription }
    }
    func refreshCSV() {
        do { try store?.writeCSV() }
        catch { self.error = "Your entries are safe in SQLite, but the CSV could not be updated. \(error.localizedDescription)" }
    }
    func export() {
        guard let store else { return }
        let panel = NSSavePanel()
        panel.title = "Export journal data"
        panel.nameFieldStringValue = "journal.csv"; panel.allowedContentTypes = [.commaSeparatedText]; panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try store.writeCSV(to: url); notice = "CSV exported with summaries and analysis fields. Audio files stay in your journal folder." }
        catch { self.error = "Export failed. \(error.localizedDescription)" }
    }
    func revealFiles() { if let store { NSWorkspace.shared.activateFileViewerSelecting([store.csvURL]) } }
}
