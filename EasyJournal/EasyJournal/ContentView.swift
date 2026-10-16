import AppKit
import SwiftUI

enum Palette {
    static let accent = Color(red: 0.24, green: 0.38, blue: 0.33)
    static let paper = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.12, green: 0.14, blue: 0.13, alpha: 1)
            : NSColor(red: 0.975, green: 0.969, blue: 0.949, alpha: 1)
    })
    static let card = Color(nsColor: .controlBackgroundColor)
}

struct ContentView: View {
    @EnvironmentObject private var journal: JournalModel
    @EnvironmentObject private var recorder: SpeechRecorder
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 235)
            Divider()
            VStack(spacing: 0) {
                HStack {
                    if journal.selected != nil && !journal.composing {
                        Button { journal.showLibrary() } label: { Label("Journal", systemImage: "chevron.left") }.buttonStyle(.plain)
                    } else { Text(journal.composing ? "New entry" : "Your journal") }
                    Spacer()
                    Label("Private · On this Mac", systemImage: "lock.shield").font(.system(size: 11))
                }.font(.system(size: 12)).foregroundStyle(.secondary).padding(.horizontal, 32).padding(.vertical, 19)
                if let error = journal.error {
                    HStack(alignment: .top) {
                        Label(error, systemImage: "exclamationmark.circle").font(.caption)
                        Spacer(); Button("Dismiss") { journal.error = nil }.buttonStyle(.plain)
                    }.padding(14).background(Color.orange.opacity(0.12)).padding(.horizontal, 32)
                }
                if journal.composing { JournalComposer() }
                else if let entry = journal.selected { JournalDetail(entry: entry).id(entry.id) }
                else { JournalLibrary() }
            }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Palette.paper)
        }.frame(minWidth: 940, minHeight: 720).tint(Palette.accent)
            .task { journal.refreshIntelligence() }
            .onChange(of: recorder.isBusy) { _, busy in
                journal.recordingInProgress = busy
                if busy { journal.analysisTask?.cancel() }
                else { journal.processPendingAnalysis() }
            }
            .onChange(of: scenePhase) { _, phase in if phase == .active { journal.refreshIntelligence() } }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label("Journal Agent", systemImage: "waveform").font(.system(size: 16, weight: .semibold)).padding(.top, 28).padding(.bottom, 30)
            Button(action: journal.newEntry) {
                Label(journal.hasDraft ? "Continue entry" : "New voice entry", systemImage: "mic.fill")
                    .font(.system(size: 12, weight: .semibold)).frame(maxWidth: .infinity).padding(12)
                    .foregroundStyle(.white).background(Palette.accent, in: RoundedRectangle(cornerRadius: 9))
            }.buttonStyle(.plain).keyboardShortcut("n").disabled(recorder.isBusy || !journal.ready)
            Button(action: journal.showLibrary) {
                HStack { Label("Journal", systemImage: "book.closed"); Spacer(); Text("\(journal.entries.count)").foregroundStyle(.secondary) }
                    .font(.system(size: 12)).padding(12)
                    .background(!journal.composing ? Palette.accent.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 8))
            }.buttonStyle(.plain).padding(.top, 10).disabled(recorder.isBusy)
            Text("RECENT").font(.system(size: 9, weight: .medium)).tracking(1.5).foregroundStyle(.secondary).padding(.top, 30).padding(.bottom, 13)
            ScrollView {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(journal.entries.prefix(8)) { entry in
                        Button { journal.selectedID = entry.id; journal.composing = false } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(entry.summaryTitle).font(.system(size: 12, weight: .medium)).lineLimit(2).multilineTextAlignment(.leading)
                                Text(entry.createdAt.formatted(.dateTime.month(.abbreviated).day())).font(.system(size: 10)).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
                                .background(journal.selectedID == entry.id && !journal.composing ? Palette.accent.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 8))
                        }.buttonStyle(.plain).disabled(recorder.isBusy)
                    }
                    if journal.entries.isEmpty { Text("Your summaries will appear here.").font(.system(size: 12)).foregroundStyle(.secondary).padding(.vertical, 8) }
                }
            }
            VStack(alignment: .leading, spacing: 9) {
                Label(journal.aiMessage == nil ? "Local AI ready" : "Local AI unavailable", systemImage: journal.aiMessage == nil ? "checkmark.circle" : "exclamationmark.circle")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                if journal.analysisID != nil { HStack { ProgressView().controlSize(.mini); Text("Creating a summary…").font(.system(size: 10)).foregroundStyle(.secondary) } }
                if let message = journal.aiMessage {
                    Text(message).font(.system(size: 10)).foregroundStyle(.secondary)
                    Button("Check again", action: journal.refreshIntelligence).font(.caption).buttonStyle(.link)
                }
            }.padding(.bottom, 16)
            Divider().padding(.bottom, 15)
            Button(action: journal.export) { Label("Export data", systemImage: "square.and.arrow.up") }.buttonStyle(.plain).font(.system(size: 12)).disabled(!journal.ready)
            Button(action: journal.revealFiles) { Label("Show journal files", systemImage: "folder") }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(.secondary).padding(.top, 14).padding(.bottom, 24).disabled(!journal.ready)
        }.padding(.horizontal, 18).background(Palette.card)
    }
}
