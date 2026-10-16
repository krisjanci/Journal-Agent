import AppKit
import SwiftUI

private enum Palette {
    static let ink = Color.primary
    static let accent = Color(red: 0.24, green: 0.38, blue: 0.33)
    static let paper = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.12, green: 0.14, blue: 0.13, alpha: 1)
            : NSColor(red: 0.975, green: 0.969, blue: 0.949, alpha: 1)
    })
}

struct ContentView: View {
    @EnvironmentObject private var journal: JournalModel
    @EnvironmentObject private var recorder: SpeechRecorder
    @State private var manualEntry = false
    @State private var baseText = ""
    @State private var baseDuration: Double = 0
    @State private var confirmDiscard = false
    @AppStorage("transcriptionLocale") private var language = "en-US"
    @FocusState private var editorFocused: Bool
    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack {
                    Label(journal.selected == nil ? "New entry" : "Your journal", systemImage: journal.selected == nil ? "circle.dotted" : "book.closed")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                    Spacer()
                    Label("On this Mac", systemImage: "lock.shield").font(.system(size: 11)).foregroundStyle(.secondary)
                }.padding(.horizontal, 36).padding(.vertical, 20)
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        composer
                        if let notice = journal.notice { Text(notice).font(.caption).foregroundStyle(Palette.accent) }
                        if let message = journal.error ?? recorder.error { errorBanner(message) }
                    }.padding(.horizontal, 48).padding(.top, 20).padding(.bottom, 40).frame(maxWidth: 880)
                        .frame(maxWidth: .infinity)
                }
            }.background(Palette.paper)
        }
        .frame(minWidth: 900, minHeight: 700)
        .tint(Palette.accent)
        .onAppear {
            recorder.onTranscript = { text, duration in
                journal.draft.text = [baseText, text].filter { !$0.isEmpty }.joined(separator: "\n\n")
                journal.draft.duration = baseDuration + duration
                if !text.isEmpty { journal.draft.source = baseText.isEmpty ? "voice" : "mixed" }
                journal.persistDraft()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { notification in
            guard let window = notification.object as? NSWindow, window.title == "Journal Agent" else { return }
            Task {
                if recorder.phase == .preparing { await recorder.cancelPreparation() }
                else if recorder.phase == .recording { _ = await recorder.finish() }
                journal.persistDraft()
            }
        }
        .onChange(of: journal.draft.text) { _, _ in journal.persistDraft() }
        .onChange(of: journal.draft.title) { _, _ in journal.persistDraft() }
        .alert("Discard this draft?", isPresented: $confirmDiscard) {
            Button("Keep writing", role: .cancel) {}
            Button("Discard", role: .destructive) { journal.discardDraft(); manualEntry = false }
        } message: { Text("This draft hasn't been added to your journal yet.") }
    }
    private var composer: some View {
        VStack(alignment: .leading, spacing: 23) {
            Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()).uppercased())
                .font(.system(size: 10, weight: .medium)).tracking(2).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 10) {
                Text("A moment for yourself.").font(.system(size: 33, weight: .regular, design: .serif))
                Text("Say what's on your mind. We'll keep the words.").font(.system(size: 14)).foregroundStyle(.secondary)
            }
            VStack(spacing: 15) {
                ZStack {
                    Circle().stroke(Palette.accent.opacity(0.07), lineWidth: 1).frame(width: 164, height: 164)
                    Circle().stroke(Palette.accent.opacity(0.12), lineWidth: 1).frame(width: 136, height: 136)
                    Circle().fill(Palette.accent.opacity(0.09)).frame(width: 110, height: 110)
                        .scaleEffect(recorder.phase == .recording ? 1 + CGFloat(recorder.level) * 0.16 : 1)
                        .animation(.easeOut(duration: 0.15), value: recorder.level)
                    Button(action: recordAction) {
                        ZStack {
                            Circle().fill(Palette.accent).frame(width: 92, height: 92)
                            if recorder.phase == .preparing || recorder.phase == .finishing { ProgressView().controlSize(.small).tint(.white) }
                            else { Image(systemName: recorder.phase == .recording ? "stop.fill" : "mic.fill").font(.system(size: 30)).foregroundStyle(.white) }
                        }
                    }.buttonStyle(.plain)
                        .disabled(!journal.ready || recorder.phase == .preparing || recorder.phase == .finishing)
                        .accessibilityLabel(recorder.phase == .recording ? "Finish recording and save entry" : "Start voice entry")
                        .keyboardShortcut("r", modifiers: [.command, .shift])
                }
                VStack(spacing: 7) {
                    Text(recorder.phase == .recording ? "Finish & save" : recorder.phase == .preparing ? "Preparing voice entry" : recorder.phase == .finishing ? "Saving your words" : "Start talking")
                        .font(.system(size: 16, weight: .medium))
                    Text(recorder.status).font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                if recorder.phase == .recording {
                    HStack(spacing: 4) {
                        Circle().fill(Color.red.opacity(0.8)).frame(width: 5, height: 5)
                        Text(duration(recorder.elapsed)).monospacedDigit().font(.system(size: 11))
                        Spacer().frame(width: 8)
                        ForEach(0..<17) { i in
                            Capsule().fill(Palette.accent.opacity(0.7)).frame(width: 3, height: 4 + CGFloat(recorder.level) * CGFloat([12, 21, 30, 16, 25][i % 5]))
                        }
                    }.frame(height: 26).animation(.easeOut(duration: 0.15), value: recorder.level)
                } else if recorder.phase == .preparing {
                    Button("Cancel setup") { Task { await recorder.cancelPreparation() } }.buttonStyle(.link).font(.caption)
                } else {
                    Text("⌘⇧R  to record").font(.system(size: 10)).foregroundStyle(.tertiary).frame(height: 26)
                }
            }.padding(.vertical, 13).frame(maxWidth: .infinity)
            HStack { Rectangle().fill(.primary.opacity(0.09)).frame(height: 1); Text("YOUR WORDS").font(.system(size: 9, weight: .medium)).tracking(1.6).foregroundStyle(.secondary).fixedSize(); Rectangle().fill(.primary.opacity(0.09)).frame(height: 1) }
            if journal.hasDraft || manualEntry || recorder.isBusy {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Give this moment a title (optional)", text: $journal.draft.title).textFieldStyle(.plain).font(.system(size: 15, weight: .medium))
                        .disabled(recorder.isBusy)
                    if recorder.isBusy {
                        Text(journal.draft.text.isEmpty ? "Your words will appear here as you speak…" : journal.draft.text)
                            .font(.system(size: 15)).lineSpacing(6).foregroundStyle(journal.draft.text.isEmpty ? .secondary : .primary)
                            .frame(maxWidth: .infinity, minHeight: 100, alignment: .topLeading).textSelection(.enabled)
                    } else {
                        TextEditor(text: $journal.draft.text).font(.system(size: 15)).lineSpacing(6)
                            .scrollContentBackground(.hidden).frame(minHeight: 135).focused($editorFocused)
                            .accessibilityLabel("Journal entry text")
                    }
                    HStack {
                        Text("\(journal.draft.wordCount) words · Draft saved locally").font(.system(size: 10)).foregroundStyle(.secondary)
                        Spacer()
                        if !recorder.isBusy {
                            Button("Discard") { confirmDiscard = true }.buttonStyle(.plain).foregroundStyle(.secondary).font(.system(size: 11))
                            Button("Save entry", action: journal.saveDraft).buttonStyle(.borderedProminent).disabled(!journal.hasDraft || !journal.ready).keyboardShortcut("s")
                        }
                    }
                }.padding(18).background(Color(nsColor: .controlBackgroundColor).opacity(0.75), in: RoundedRectangle(cornerRadius: 10))
            } else {
                Button {
                    manualEntry = true; editorFocused = true
                } label: { Label("Prefer to write? Add a manual entry", systemImage: "pencil.line").font(.system(size: 12)).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 10) }
                    .buttonStyle(.plain).disabled(!journal.ready)
            }
            HStack(alignment: .top, spacing: 7) {
                Image(systemName: "lock").font(.system(size: 10))
                Text("Transcribed on your Mac. No audio is stored. Entries are saved locally with an automatic CSV copy.").font(.system(size: 10)).lineSpacing(3)
                Spacer(minLength: 10)
                Picker("Language", selection: $language) {
                    Text("English (US)").tag("en-US"); Text("English (UK)").tag("en-GB")
                    Text("Español").tag("es-ES"); Text("Français").tag("fr-FR")
                    Text("Deutsch").tag("de-DE"); Text("Italiano").tag("it-IT")
                    Text("Português (BR)").tag("pt-BR"); Text("日本語").tag("ja-JP")
                }.labelsHidden().frame(width: 125).controlSize(.small).disabled(recorder.isBusy)
            }.foregroundStyle(.secondary)
        }
    }
    private func errorBanner(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Something needs attention", systemImage: "exclamationmark.circle").font(.system(size: 12, weight: .semibold))
            Text(message).font(.system(size: 12)).textSelection(.enabled)
            Button("Dismiss") { journal.error = nil; recorder.error = nil }.buttonStyle(.link).font(.caption)
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
    }
    private func recordAction() {
        if recorder.phase == .recording {
            Task {
                if await recorder.finish() {
                    if journal.hasDraft { journal.saveDraft(); manualEntry = false }
                    else { recorder.error = "No speech was detected. Check your microphone input and try again." }
                }
            }
        } else if recorder.phase == .idle {
            baseText = journal.draft.text; baseDuration = journal.draft.duration
            journal.notice = nil
            recorder.start(localeID: language)
        }
    }
    private func duration(_ seconds: Double) -> String { String(format: "%02d:%02d", Int(seconds) / 60, Int(seconds) % 60) }
}
