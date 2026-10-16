import Foundation

/// AI interprets the query; deterministic evidence checks prevent invented result IDs or match claims.
enum JournalRetrieval {
    static func matches(query: String, intent: SearchIntent, entries: [JournalEntry]) -> [JournalSearchMatch] {
        let stopWords: Set<String> = ["a", "an", "the", "i", "my", "me", "when", "did", "do", "was", "were", "is", "are", "on", "in", "of", "to", "for", "and", "or", "about", "entry", "entries", "find", "show", "journal", "time", "times", "something"]
        func terms(_ values: [String]) -> [String] {
            Array(Set(values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { $0.count >= 2 && $0.count <= 80 && !stopWords.contains($0) })).sorted()
        }
        let generic = Set(["progress", "time", "day", "days", "moment", "entry", "entries", "experience"])
        let concepts = intent.concepts.count > 1 ? intent.concepts.filter { !generic.contains($0.concept.lowercased()) } : intent.concepts
        let groups = concepts.map { terms([$0.concept] + $0.alternatives) }.filter { !$0.isEmpty }
        let fallback = terms(query.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
        let excluded = terms(intent.excludedTerms.filter { query.localizedCaseInsensitiveContains($0) })
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"; formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.isLenient = false
        let hasDateRequest = query.range(of: #"\b(today|yesterday|tomorrow|week|month|year|january|february|march|april|may|june|july|august|september|october|november|december|monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b|\d{4}-\d{2}-\d{2}"#, options: [.regularExpression, .caseInsensitive]) != nil
        let start = hasDateRequest ? formatter.date(from: intent.startDate) : nil
        let end = (hasDateRequest ? formatter.date(from: intent.endDate) : nil).flatMap { Calendar.current.date(byAdding: .day, value: 1, to: $0) }
        var result: [JournalSearchMatch] = []
        for entry in entries {
            if let start, entry.createdAt < start { continue }
            if let end, entry.createdAt >= end { continue }
            let text = entry.currentAnalysis?.searchText ?? entry.text
            if excluded.contains(where: { contains($0, in: text) }) { continue }
            let groupHits = groups.map { $0.filter { contains($0, in: text) } }
            let hits: [String]
            if !groups.isEmpty {
                guard groupHits.allSatisfy({ !$0.isEmpty }) else { continue }
                hits = groupHits.flatMap { $0 }
            } else {
                hits = fallback.filter { contains($0, in: text) }
                guard !hits.isEmpty || start != nil || end != nil else { continue }
            }
            let unique = Array(Set(hits)).sorted()
            let literal = contains(query, in: text)
            result.append(JournalSearchMatch(id: entry.id, relevance: unique.count + (literal ? 10 : 0),
                reason: unique.isEmpty ? "Within the requested date range" : "Related to " + unique.prefix(4).joined(separator: ", ")))
        }
        let dates = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0.createdAt) })
        return result.sorted {
            if $0.relevance != $1.relevance { return $0.relevance > $1.relevance }
            return dates[$0.id, default: .distantPast] > dates[$1.id, default: .distantPast]
        }
    }
    static func contains(_ term: String, in text: String) -> Bool {
        guard !term.isEmpty else { return false }
        let pattern = "(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: term) + "(?![\\p{L}\\p{N}])"
        return text.range(of: pattern, options: [.regularExpression, .caseInsensitive, .diacriticInsensitive]) != nil
    }
}
