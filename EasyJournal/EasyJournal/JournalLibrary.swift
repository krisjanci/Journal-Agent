import SwiftUI

struct JournalLibrary: View {
    @EnvironmentObject private var journal: JournalModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 23) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your days, made clear.").font(.system(size: 31, weight: .regular, design: .serif))
                    Text("Browse the highlights. Find the moments that matter.").font(.system(size: 13)).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Image(systemName: "sparkle.magnifyingglass").foregroundStyle(.secondary)
                        TextField("Ask your journal…", text: $journal.searchQuery).textFieldStyle(.plain).font(.system(size: 14)).onSubmit { journal.runSearch() }
                            .accessibilityLabel("Search journal by meaning")
                        if !journal.searchQuery.isEmpty { Button { journal.clearSearch() } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain).help("Clear search") }
                        Button("Search", action: journal.runSearch).buttonStyle(.borderedProminent).disabled(journal.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }.padding(15).background(Palette.card, in: RoundedRectangle(cornerRadius: 10))
                    Text("Try “when did I make progress on a project?” or “time spent outside”. Press Return to search.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }.onChange(of: journal.searchQuery) { _, _ in journal.invalidateSearch() }
                if journal.searching {
                    HStack { ProgressView().controlSize(.small); Text(journal.searchStatus).font(.system(size: 12)); Spacer(); Button("Cancel", action: journal.cancelSearch).buttonStyle(.plain) }
                } else if !journal.searchedQuery.isEmpty {
                    HStack {
                        Label(journal.searchStatus, systemImage: journal.keywordFallback ? "text.magnifyingglass" : "sparkles").font(.system(size: 12)).foregroundStyle(.secondary)
                        Spacer(); Button("Show all", action: journal.clearSearch).buttonStyle(.plain).font(.system(size: 12))
                    }
                } else {
                    Text("\(journal.entries.count) \(journal.entries.count == 1 ? "ENTRY" : "ENTRIES")").font(.system(size: 10, weight: .medium)).tracking(1.5).foregroundStyle(.secondary)
                }
                if let error = journal.searchError { Text(error).font(.system(size: 12)).foregroundStyle(.secondary).padding(14).background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8)) }
                if !journal.searching && journal.visibleEntries.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(journal.entries.isEmpty ? "Begin with a moment." : "No matching entries.").font(.system(size: 21, design: .serif))
                        Text(journal.entries.isEmpty ? "Speak or write an entry. Its summary will appear here." : "Try describing the moment another way, or browse all entries.").font(.system(size: 13)).foregroundStyle(.secondary)
                        if journal.entries.isEmpty { Button("Create an entry", action: journal.newEntry).buttonStyle(.borderedProminent) }
                    }.padding(.vertical, 30)
                }
                if !journal.searching {
                    LazyVStack(spacing: 13) {
                        ForEach(journal.visibleEntries) { entry in
                            Button { journal.selectedID = entry.id; journal.composing = false } label: {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        Text(entry.createdAt.formatted(.dateTime.month(.abbreviated).day().year())).font(.system(size: 10)).foregroundStyle(.secondary)
                                        Spacer()
                                        Image(systemName: entry.source == "manual" ? "pencil.line" : "waveform").font(.system(size: 11)).foregroundStyle(.secondary)
                                    }
                                    Text(entry.summaryTitle).font(.system(size: 19, weight: .medium, design: .serif))
                                    Text(entry.summaryPreview).font(.system(size: 13)).lineSpacing(4).foregroundStyle(.secondary).lineLimit(4)
                                    if let reason = journal.searchMatches?.first(where: { $0.id == entry.id })?.reason {
                                        Label(reason, systemImage: journal.keywordFallback ? "magnifyingglass" : "sparkles").font(.system(size: 11)).foregroundStyle(.secondary)
                                    }
                                    if let analysis = entry.currentAnalysis, !analysis.topics.isEmpty {
                                        Text(analysis.topics.prefix(4).joined(separator: "  ·  ")).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                                    } else if journal.analysisFailures[entry.id] != nil { Text("Summary needs another try").font(.caption).foregroundStyle(.secondary) }
                                }.frame(maxWidth: .infinity, alignment: .leading).padding(21).background(Palette.card, in: RoundedRectangle(cornerRadius: 11))
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }.padding(34).frame(maxWidth: 900).frame(maxWidth: .infinity)
        }
    }
}
