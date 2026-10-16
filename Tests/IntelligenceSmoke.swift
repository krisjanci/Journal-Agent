import Foundation
import Darwin

@main struct IntelligenceSmoke {
    static func main() async throws {
        setbuf(stdout, nil)
        if let message = JournalIntelligence.availabilityMessage { throw JournalFailure(message: message) }
        let ai = JournalIntelligence()
        var work = JournalEntry(id: "work", text: "Today I fixed the FocusFix prediction bug and finished the regression evaluation. I felt proud of solving it. Tomorrow I plan to write the results section.")
        var outside = JournalEntry(id: "outside", text: "I walked along the river for half an hour and watched ducks. Later I cooked vegetable soup for dinner.")
        work.analysis = try await ai.analyze(work)
        outside.analysis = try await ai.analyze(outside)
        print("Work summary: \(work.analysis!.summary)")
        print("Plans: \(work.analysis!.nextSteps)")
        print("Outside analysis: \(outside.analysis!.searchText)")
        guard work.analysis!.isCurrent(for: work.text), !work.analysis!.summary.isEmpty,
              !work.analysis!.nextSteps.isEmpty else { throw JournalFailure(message: "The test summary is incomplete.") }
        guard outside.analysis!.nextSteps.isEmpty, outside.analysis!.feelings.isEmpty else {
            throw JournalFailure(message: "The analysis invented plans or feelings for the neutral entry.")
        }
        let query = "When did I make progress on my machine learning project?"
        let intent = try await ai.interpretSearch(query)
        print("Intent: \(intent)")
        let matches = JournalRetrieval.matches(query: query, intent: intent, entries: [outside, work])
        print("Matches: \(matches.map(\.id))")
        guard matches.contains(where: { $0.id == "work" }), !matches.contains(where: { $0.id == "outside" }) else {
            throw JournalFailure(message: "Semantic search did not distinguish the two sample entries.")
        }
        let none = try await ai.search("When did I repair a bicycle tire?", entries: [outside, work]) { _, _ in }
        print("Unrelated matches: \(none)")
        guard none.isEmpty else { throw JournalFailure(message: "Unrelated search returned a false match.") }
        print("PASS: actual local AI summaries, planned actions, semantic retrieval, and no-match search")
    }
}
