import FoundationModels

@Generable
struct AnalysisOutput {
    @Guide(description: "A short factual title, at most eight words")
    var title: String
    @Guide(description: "A useful factual summary in two or three short sentences. Preserve important events and outcomes. No advice.")
    var summary: String
    @Guide(description: "Specific short topic labels, such as project names, exercise, or family", .maximumCount(6))
    var topics: [String]
    @Guide(description: "Activities that actually happened; short phrases", .maximumCount(5))
    var activities: [String]
    @Guide(description: "Completed outcomes explicitly described; empty if none", .maximumCount(4))
    var accomplishments: [FactOutput]
    @Guide(description: "Future actions or intentions explicitly stated by the writer; never invent tasks", .maximumCount(4))
    var nextSteps: [FactOutput]
    @Guide(description: "Feelings explicitly named by the writer, with an exact supporting quote; empty if none", .maximumCount(4))
    var feelings: [FeelingOutput]
}

@Generable
struct FactOutput {
    @Guide(description: "A concise factual description of this outcome or plan")
    var item: String
    @Guide(description: "An exact source quote supporting this fact. A plan quote must explicitly express a future intention; past events are not plans.")
    var quote: String
}

@Generable
struct FeelingOutput {
    var feeling: String
    @Guide(description: "A short exact quote copied from the source that explicitly states this feeling")
    var quote: String
}

@Generable
struct SearchIntent {
    @Guide(description: "One to three essential concepts in the search. Each concept contains synonyms or specific examples. Exclude filler words like when, entries, about, or find.", .maximumCount(3))
    var concepts: [SearchConcept]
    @Guide(description: "Only terms explicitly excluded by the query, otherwise empty", .maximumCount(4))
    var excludedTerms: [String]
    @Guide(description: "Start date as YYYY-MM-DD only when the query specifies a date range; otherwise an empty string")
    var startDate: String
    @Guide(description: "End date as YYYY-MM-DD only when the query specifies a date range; otherwise an empty string")
    var endDate: String
}

@Generable
struct SearchConcept {
    @Guide(description: "The essential concept, copied as a short phrase from the query")
    var concept: String
    @Guide(description: "Short search terms: this concept plus closely related synonyms, inflections, and specific examples; not broad associations", .maximumCount(10))
    var alternatives: [String]
}
