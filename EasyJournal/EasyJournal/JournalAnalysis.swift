import CryptoKit
import Foundation

struct FeelingEvidence: Codable, Equatable, Sendable {
    var feeling: String
    var quote: String
}

struct JournalAnalysis: Codable, Equatable, Sendable {
    static let currentVersion = 1
    var title: String
    var summary: String
    var topics: [String]
    var activities: [String]
    var accomplishments: [String]
    var nextSteps: [String]
    var feelings: [FeelingEvidence]
    var generatedAt: Date = Date()
    var sourceHash: String
    var version: Int = currentVersion
    var engine: String = "Apple on-device Foundation Models"
    var systemVersion: String = ProcessInfo.processInfo.operatingSystemVersionString

    static func hash(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    func isCurrent(for text: String) -> Bool {
        version == Self.currentVersion && sourceHash == Self.hash(text)
    }
    var searchText: String {
        ([title, summary] + topics + activities + accomplishments + nextSteps + feelings.map(\.feeling)).joined(separator: "\n")
    }
}

struct JournalSearchMatch: Identifiable, Equatable, Sendable {
    let id: String
    let relevance: Int
    let reason: String
}

/// Character-bounded chunks avoid dropping the end of a long journal entry.
enum JournalText {
    /// Conservative evidence check: past actions must not silently become future plans.
    static func hasFutureIntent(_ quote: String) -> Bool {
        let cues = ["will", "i'll", "we'll", "plan", "planning", "intend", "going to", "want to", "need to", "have to", "tomorrow", "next week", "next month", "demain", "prévois", "je vais", "mañana", "quiero", "planeo", "voy a", "morgen", "werde", "vorhaben", "domani", "voglio", "amanhã", "pretendo", "明日", "予定"]
        return cues.contains { cue in
            quote.range(of: "(?<![\\p{L}])" + NSRegularExpression.escapedPattern(for: cue) + "(?![\\p{L}])", options: [.regularExpression, .caseInsensitive]) != nil
        }
    }
    static func chunks(_ text: String, limit: Int = 2800) -> [String] {
        precondition(limit > 0)
        var remaining = text[...]
        var result: [String] = []
        while !remaining.isEmpty {
            let boundary = remaining.index(remaining.startIndex, offsetBy: limit, limitedBy: remaining.endIndex) ?? remaining.endIndex
            var end = boundary
            if boundary != remaining.endIndex {
                let tailStart = remaining.index(remaining.startIndex, offsetBy: limit / 2)
                if let breakAt = remaining[tailStart..<boundary].lastIndex(where: \.isWhitespace) {
                    end = remaining.index(after: breakAt)
                }
            }
            result.append(String(remaining[..<end]))
            remaining = remaining[end...]
        }
        return result
    }
}
