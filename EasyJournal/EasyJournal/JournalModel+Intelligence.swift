import Foundation

@MainActor
extension JournalModel {
    func refreshIntelligence() {
        aiMessage = JournalIntelligence.availabilityMessage
        if aiMessage == nil { processPendingAnalysis() }
    }
    func processPendingAnalysis() {
        guard analysisTask == nil, !searching, !recordingInProgress, ready, JournalIntelligence.availabilityMessage == nil else { return }
        analysisTask = Task { [weak self] in
            guard let self else { return }
            defer {
                self.analysisID = nil; self.analysisTask = nil
                if Task.isCancelled { Task { self.processPendingAnalysis() } }
            }
            while !Task.isCancelled, !self.searching {
                guard let entry = self.entries.first(where: {
                    $0.currentAnalysis == nil && !$0.text.isEmpty && self.analysisFailures[$0.id] == nil
                }) else { break }
                self.analysisID = entry.id
                do {
                    let analysis = try await self.intelligence.analyze(entry)
                    try Task.checkCancellation()
                    guard self.entries.first(where: { $0.id == entry.id })?.text == entry.text else { continue }
                    try self.store?.saveAnalysis(analysis, for: entry.id)
                    self.entries = try self.store?.entries() ?? self.entries
                    self.refreshCSV()
                } catch {
                    if Task.isCancelled { break }
                    self.analysisFailures[entry.id] = "Couldn't create a summary. \(error.localizedDescription)"
                }
            }
        }
    }
    func retryAnalysis(_ entry: JournalEntry) {
        analysisFailures[entry.id] = nil
        refreshIntelligence()
    }
    func invalidateSearch() {
        searchToken = UUID(); searchTask?.cancel(); searchTask = nil
        searching = false; searchedQuery = ""; searchMatches = nil; searchStatus = ""; searchError = nil; keywordFallback = false
    }
    func clearSearch() { searchQuery = ""; invalidateSearch(); processPendingAnalysis() }
    func cancelSearch() { invalidateSearch(); processPendingAnalysis() }
    func runSearch() {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { clearSearch(); return }
        guard query.count <= 500 else { searchError = "Please keep your search under 500 characters."; return }
        let previousSearch = searchTask
        invalidateSearch()
        let token = searchToken
        searchedQuery = query; searching = true; composing = false; selectedID = nil
        searchStatus = "Searching your journal by meaning…"
        // Finish cancellation of active summarization before starting another model session.
        let oldAnalysis = analysisTask
        oldAnalysis?.cancel()
        searchTask = Task { [weak self] in
            guard let self else { return }
            await previousSearch?.value
            await oldAnalysis?.value
            guard !Task.isCancelled, self.searchToken == token else { return }
            defer {
                if self.searchToken == token {
                    self.searching = false; self.searchTask = nil; self.processPendingAnalysis()
                }
            }
            do {
                let matches = try await self.intelligence.search(query, entries: self.entries) { [weak self] completed, total in
                    await MainActor.run { [weak self] in
                        guard let self, self.searchToken == token else { return }
                        self.searchStatus = "Checked \(completed) of \(total) passages…"
                    }
                }
                guard !Task.isCancelled, self.searchToken == token else { return }
                self.searchMatches = matches
                self.searchStatus = "\(matches.count) \(matches.count == 1 ? "entry" : "entries") found by meaning"
            } catch {
                guard !Task.isCancelled, self.searchToken == token else { return }
                self.searchError = "AI search couldn't finish. Showing exact-text matches instead. \(error.localizedDescription)"
                self.keywordFallback = true
                self.searchMatches = self.entries.filter {
                    ($0.currentAnalysis?.searchText ?? $0.text).localizedCaseInsensitiveContains(query)
                }.map { JournalSearchMatch(id: $0.id, relevance: 1, reason: "Text match") }
                self.searchStatus = "\(self.searchMatches?.count ?? 0) text matches"
            }
        }
    }
}
