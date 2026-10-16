import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

@MainActor
final class JournalModel: ObservableObject {
    @Published var entries: [JournalEntry] = []
    @Published var draft = JournalEntry()
    @Published var selectedID: String?
    @Published var error: String?
    @Published var notice: String?
    @Published var ready = false
    private var store: JournalStore?

    init() {
        do {
            let store = try JournalStore()
            self.store = store
            entries = try store.entries()
            draft = try store.draft() ?? JournalEntry()
            ready = true
            refreshCSV()
        } catch { self.error = "Your journal could not be opened. \(error.localizedDescription)" }
    }
    var selected: JournalEntry? { entries.first { $0.id == selectedID } }
    var hasDraft: Bool { !draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    func persistDraft() {
        guard let store else { return }
        do { try store.saveDraft(draft) }
        catch { self.error = "Your draft could not be saved. \(error.localizedDescription)" }
    }
    func saveDraft() {
        guard let store, hasDraft else { return }
        var entry = draft
        entry.text = entry.text.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.updatedAt = Date()
        do {
            try store.save(entry, clearingDraft: true)
            draft = JournalEntry()
            entries = try store.entries()
            selectedID = entry.id
            notice = "Entry saved on this Mac."
            refreshCSV()
        } catch { self.error = "Couldn't save your entry. Your draft is still here. \(error.localizedDescription)" }
    }
    func update(_ entry: JournalEntry) -> Bool {
        guard let store else { return false }
        do {
            var revised = entry; revised.updatedAt = Date()
            try store.save(revised)
            entries = try store.entries()
            notice = "Changes saved."
            refreshCSV()
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func delete(_ entry: JournalEntry) {
        guard let store else { return }
        do {
            try store.delete(entry.id)
            entries = try store.entries(); selectedID = nil
            refreshCSV()
        } catch { self.error = error.localizedDescription }
    }
    func discardDraft() {
        do { try store?.clearDraft(); draft = JournalEntry() }
        catch { self.error = error.localizedDescription }
    }
    func refreshCSV() {
        do { try store?.writeCSV() }
        catch { self.error = "Your entries are safe in SQLite, but the CSV could not be updated. \(error.localizedDescription)" }
    }
    func export() {
        guard let store else { return }
        let panel = NSSavePanel()
        panel.title = "Export your journal"
        panel.nameFieldStringValue = "journal.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try store.writeCSV(to: url); notice = "CSV exported." }
        catch { self.error = "Export failed. \(error.localizedDescription)" }
    }
    func revealFiles() {
        guard let store else { return }
        NSWorkspace.shared.activateFileViewerSelecting([store.csvURL])
    }
}
