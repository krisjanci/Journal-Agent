import Foundation

@main struct RetrievalTests {
    static func main() {
        let oldDate = Date(timeIntervalSince1970: 1_700_000_000)
        let work = JournalEntry(id: "work", createdAt: oldDate, text: "Fixed a prediction model and completed regression evaluation.")
        let walk = JournalEntry(id: "walk", text: "Walked by the river and cooked soup.")
        let query = "When did I make progress on machine learning?"
        let intent = SearchIntent(concepts: [SearchConcept(concept: "machine learning", alternatives: ["prediction", "regression", "model"])], excludedTerms: [], startDate: "2026-10-16", endDate: "2026-10-16")
        let matches = JournalRetrieval.matches(query: query, intent: intent, entries: [walk, work])
        precondition(matches.map(\.id) == ["work"], "An invented date restriction must not hide old entries")
        let bike = SearchIntent(concepts: [SearchConcept(concept: "bicycle", alternatives: ["bike", "tire", "puncture"])], excludedTerms: [], startDate: "", endDate: "")
        precondition(JournalRetrieval.matches(query: "bicycle repair", intent: bike, entries: [work, walk]).isEmpty)
        precondition(!JournalRetrieval.contains("run", in: "prune"))
        precondition(JournalRetrieval.contains("regression", in: "Regression evaluation"))
        let noDates = SearchIntent(concepts: [], excludedTerms: [], startDate: "", endDate: "")
        precondition(JournalRetrieval.matches(query: "river", intent: noDates, entries: [work, walk]).map(\.id) == ["walk"])
        precondition(JournalText.hasFutureIntent("Tomorrow I plan to write the results."))
        precondition(!JournalText.hasFutureIntent("I walked outside and cooked dinner."))
        let original = String(repeating: "quiet day. ", count: 1000) + "I saw a bicycle."
        precondition(JournalRetrieval.matches(query: "bicycle", intent: bike, entries: [JournalEntry(text: original)]).count == 1)
        print("PASS: grounded concept retrieval, old entries, no-match queries, word boundaries, full-text fallback, future-intent checks")
    }
}
