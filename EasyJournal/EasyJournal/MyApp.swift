import AppKit
import SwiftUI

@MainActor
final class JournalAppDelegate: NSObject, NSApplicationDelegate {
    var beforeQuit: (() async -> Void)?
    var shouldFinish: (() -> Bool)?
    private var finishingQuit = false
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !finishingQuit, shouldFinish?() == true, let beforeQuit else { return .terminateNow }
        finishingQuit = true
        Task {
            await beforeQuit()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

@main
struct MyApp: App {
    @NSApplicationDelegateAdaptor(JournalAppDelegate.self) private var appDelegate
    @StateObject private var journal = JournalModel()
    @StateObject private var recorder = SpeechRecorder()
    var body: some Scene {
        Window("Journal Agent", id: "journal") {
            ContentView().environmentObject(journal).environmentObject(recorder)
                .onAppear {
                    appDelegate.shouldFinish = { recorder.isBusy }
                    appDelegate.beforeQuit = {
                        if recorder.phase == .preparing { await recorder.cancelPreparation() }
                        else if recorder.phase == .recording { _ = await recorder.finish() }
                        while recorder.phase == .finishing { try? await Task.sleep(for: .milliseconds(100)) }
                        journal.persistDraft()
                    }
                }
        }
        .defaultSize(width: 1080, height: 810)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .saveItem) {
                Button("Export journal as CSV…", action: journal.export).keyboardShortcut("e", modifiers: [.command, .shift])
                Button("Show journal files", action: journal.revealFiles)
            }
        }
    }
}
