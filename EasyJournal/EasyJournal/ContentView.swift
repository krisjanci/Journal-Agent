import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var journal: JournalModel
    @EnvironmentObject private var recorder: SpeechRecorder
    @State private var baseText = ""
    @State private var baseDuration: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Journal Agent").font(.largeTitle.bold())
            Text("Say what's on your mind.").foregroundStyle(.secondary)
            Button {
                if recorder.phase == .recording {
                    Task {
                        if await recorder.finish() {
                            if journal.hasDraft { journal.saveDraft() }
                            else { recorder.error = "No speech was detected. Check your microphone input and try again." }
                        }
                    }
                } else {
                    baseText = journal.draft.text
                    baseDuration = journal.draft.duration
                    journal.notice = nil
                    recorder.start(localeID: "en-US")
                }
            } label: {
                Image(systemName: recorder.phase == .recording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 36)).foregroundStyle(.white)
                    .frame(width: 90, height: 90).background(Color.accentColor, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!journal.ready || recorder.phase == .preparing || recorder.phase == .finishing)
            .accessibilityLabel(recorder.phase == .recording ? "Finish recording and save entry" : "Start voice entry")
            Text(recorder.status).foregroundStyle(.secondary)
            if recorder.phase == .preparing {
                Button("Cancel setup") { Task { await recorder.cancelPreparation() } }
            }
            ScrollView {
                Text(journal.draft.text).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
            }.frame(minHeight: 140)
            if let notice = journal.notice { Text(notice).foregroundStyle(.secondary) }
            if let error = journal.error ?? recorder.error { Text(error).foregroundStyle(.red) }
        }
        .padding(40).frame(minWidth: 600, minHeight: 500)
        .onAppear {
            recorder.onTranscript = { text, duration in
                journal.draft.text = [baseText, text].filter { !$0.isEmpty }.joined(separator: "\n\n")
                journal.draft.duration = baseDuration + duration
                if !text.isEmpty { journal.draft.source = baseText.isEmpty ? "voice" : "mixed" }
                journal.persistDraft()
            }
        }
    }
}
