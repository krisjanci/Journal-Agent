import SwiftUI

struct JournalDetail: View {
    @EnvironmentObject private var journal: JournalModel
    let entry: JournalEntry
    @State private var showingOriginal = false
    @State private var editing = false
    @State private var confirmingDelete = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(entry.createdAt.formatted(.dateTime.weekday(.wide).month(.wide).day().year()).uppercased())
                    .font(.system(size: 10, weight: .medium)).tracking(1.4).foregroundStyle(.secondary)
                Text(entry.summaryTitle).font(.system(size: 32, weight: .regular, design: .serif)).textSelection(.enabled)
                if let analysis = entry.currentAnalysis {
                    VStack(alignment: .leading, spacing: 16) {
                        Label("SUMMARY", systemImage: "sparkles").font(.system(size: 10, weight: .medium)).tracking(1.2).foregroundStyle(.secondary)
                        Text(analysis.summary).font(.system(size: 17)).lineSpacing(7).textSelection(.enabled)
                    }
                    if !analysis.topics.isEmpty { Text(analysis.topics.joined(separator: "  ·  ")).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary).textSelection(.enabled) }
                    Divider()
                    facts("Activities", items: analysis.activities, icon: "list.bullet")
                    facts("Accomplishments", items: analysis.accomplishments, icon: "checkmark.circle")
                    facts("Stated plans", items: analysis.nextSteps, icon: "arrow.up.right.circle")
                    if !analysis.feelings.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Expressed feelings", systemImage: "quote.bubble").font(.system(size: 12, weight: .semibold))
                            ForEach(Array(analysis.feelings.enumerated()), id: \.offset) { _, feeling in
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(feeling.feeling.capitalized).font(.system(size: 13, weight: .medium))
                                    Text("“\(feeling.quote)”").font(.system(size: 12)).foregroundStyle(.secondary).textSelection(.enabled)
                                }
                            }
                        }
                    }
                    Text("Created on this Mac with Apple Intelligence. AI summaries can miss details; your original is below.")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        if journal.analysisID == entry.id {
                            HStack { ProgressView().controlSize(.small); Text("Creating your summary…").font(.system(size: 14)) }
                            Text("Your original entry is already saved.").font(.system(size: 12)).foregroundStyle(.secondary)
                        } else {
                            Text(entry.text.isEmpty ? "Audio saved. Add a transcript to create a summary." : "Your summary is not ready yet.").font(.system(size: 15))
                            if let failure = journal.analysisFailures[entry.id] ?? journal.aiMessage { Text(failure).font(.system(size: 12)).foregroundStyle(.secondary) }
                            if !entry.text.isEmpty { Button("Create summary") { journal.retryAnalysis(entry) }.buttonStyle(.bordered).disabled(journal.searching) }
                        }
                    }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(Palette.card, in: RoundedRectangle(cornerRadius: 10))
                }
                Divider()
                DisclosureGroup(isExpanded: $showingOriginal) {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(Array((entry.audioFiles ?? []).enumerated()), id: \.element) { offset, name in
                            if let url = journal.audioURL(name) { AudioClipView(url: url, number: offset + 1) }
                        }
                        if entry.source != "manual" && (entry.audioFiles ?? []).isEmpty {
                            Text("This older entry has a transcript only; its recording wasn't retained.").font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        Text(entry.text.isEmpty ? "No transcript is available for this recording." : entry.text)
                            .font(.system(size: 14)).lineSpacing(6).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                        HStack {
                            Text("\(entry.wordCount) words").font(.system(size: 10)).foregroundStyle(.secondary)
                            Spacer(); Button("Edit original") { editing = true }.buttonStyle(.bordered)
                        }
                    }.padding(.top, 18)
                } label: {
                    HStack {
                        Label("Original entry", systemImage: "waveform.and.mic")
                        Spacer()
                        Text((entry.audioFiles ?? []).isEmpty ? "Transcript" : "Audio & transcript").foregroundStyle(.secondary)
                    }.font(.system(size: 12, weight: .medium))
                }
                HStack {
                    Label("Saved locally", systemImage: "lock").font(.system(size: 10)).foregroundStyle(.secondary)
                    Spacer()
                    Button("Delete entry") { confirmingDelete = true }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary)
                }.padding(.top, 12)
            }.padding(36).frame(maxWidth: 840).frame(maxWidth: .infinity)
        }
        .sheet(isPresented: $editing) { OriginalEntryEditor(entry: entry) { journal.update($0) } }
        .alert("Delete this entry?", isPresented: $confirmingDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { journal.delete(entry) }
        } message: { Text("This removes the summary, transcript, and recordings from this Mac. Exported copies aren't changed.") }
    }
    @ViewBuilder private func facts(_ title: String, items: [String], icon: String) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 11) {
                Label(title, systemImage: icon).font(.system(size: 12, weight: .semibold))
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 10) { Text("·").foregroundStyle(.secondary); Text(item).textSelection(.enabled) }.font(.system(size: 14)).lineSpacing(4)
                }
            }
        }
    }
}

private struct OriginalEntryEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var entry: JournalEntry
    var save: (JournalEntry) -> Bool
    @State private var saveFailed = false
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Edit original entry").font(.title2.weight(.semibold))
            Text("The summary will refresh after changes to the transcript. Your recording stays unchanged.").font(.caption).foregroundStyle(.secondary)
            if saveFailed { Text("Could not save changes. Your edits are still here; please try again.").foregroundStyle(.red).font(.caption) }
            TextField("Title override (optional)", text: $entry.title).textFieldStyle(.roundedBorder)
            TextEditor(text: $entry.text).font(.body).frame(minHeight: 250).border(.secondary.opacity(0.15)).accessibilityLabel("Original transcript")
            HStack { Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction); Spacer()
                Button("Save changes") { if save(entry) { dismiss() } else { saveFailed = true } }.buttonStyle(.borderedProminent)
                    .disabled(entry.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (entry.audioFiles ?? []).isEmpty).keyboardShortcut(.defaultAction)
            }
        }.padding(28).frame(width: 570).tint(Palette.accent)
    }
}
