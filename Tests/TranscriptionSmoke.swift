import AVFoundation
import Foundation
import Speech

@main
struct TranscriptionSmoke {
    static func main() async throws {
        guard CommandLine.arguments.count == 2 else { throw JournalFailure(message: "Pass a local audio file path.") }
        guard SpeechTranscriber.isAvailable,
              let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "en-US")) else {
            throw JournalFailure(message: "On-device speech is not available on this machine.")
        }
        let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        print("Model status: \(await AssetInventory.status(forModules: [transcriber]))")
        if let installation = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            print("Preparing English speech model…")
            try await installation.downloadAndInstall()
        }
        let audio = try AVAudioFile(forReading: URL(fileURLWithPath: CommandLine.arguments[1]))
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber], considering: audio.processingFormat) else {
            throw JournalFailure(message: "No compatible speech format")
        }
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        try await analyzer.prepareToAnalyze(in: format)
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        let results = Task { () throws -> String in
            var transcript = ""
            for try await result in transcriber.results {
                if result.isFinal { transcript += String(result.text.characters) }
            }
            return transcript
        }
        try await analyzer.start(inputSequence: stream)
        let recordingURL = FileManager.default.temporaryDirectory.appendingPathComponent("JournalAudioTest-\(UUID()).caf")
        defer { try? FileManager.default.removeItem(at: recordingURL) }
        let recording = try AVAudioFile(forWriting: recordingURL, settings: format.settings)
        let bridge = try AudioBridge(source: audio.processingFormat, target: format, continuation: continuation,
            recording: recording, level: { _ in }, failure: { message in fatalError(message) })
        while audio.framePosition < audio.length {
            let buffer = AVAudioPCMBuffer(pcmFormat: audio.processingFormat, frameCapacity: 4096)!
            try audio.read(into: buffer)
            bridge.accept(buffer)
        }
        continuation.finish()
        try await analyzer.finalizeAndFinishThroughEndOfInput()
        let text = try await results.value
        print("Transcript: \(text)")
        guard text.lowercased().contains("journal"), text.lowercased().contains("walk") else {
            throw JournalFailure(message: "Expected test words were not transcribed.")
        }
        guard recording.length > 0 else { throw JournalFailure(message: "Recording was empty") }
        print("PASS: audio conversion, retained recording, and on-device transcription")
    }
}
