import AVFoundation
import Combine
import Foundation
import Speech

/// Only the audio callback touches the converter. No UI-isolated state is used on the audio thread.
final class AudioBridge: @unchecked Sendable {
    let continuation: AsyncStream<AnalyzerInput>.Continuation
    let targetFormat: AVAudioFormat
    let converter: AVAudioConverter?
    let level: @Sendable (Float) -> Void
    let failure: @Sendable (String) -> Void

    init(source: AVAudioFormat, target: AVAudioFormat, continuation: AsyncStream<AnalyzerInput>.Continuation,
         level: @escaping @Sendable (Float) -> Void, failure: @escaping @Sendable (String) -> Void) throws {
        self.continuation = continuation; targetFormat = target; self.level = level; self.failure = failure
        converter = source == target ? nil : AVAudioConverter(from: source, to: target)
        if source != target && converter == nil { throw JournalFailure(message: "This microphone's audio format isn't supported. Choose another input in System Settings → Sound.") }
    }
    func accept(_ buffer: AVAudioPCMBuffer) {
        if let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 {
            var sum: Float = 0
            for i in 0..<Int(buffer.frameLength) { sum += samples[i] * samples[i] }
            let rms = sqrt(sum / Float(buffer.frameLength))
            level(min(1, max(0, (20 * log10(max(rms, 0.00001)) + 55) / 55)))
        }
        guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat,
            frameCapacity: AVAudioFrameCount(ceil(Double(buffer.frameLength) * targetFormat.sampleRate / buffer.format.sampleRate)) + 32) else { return }
        if let converter {
            var supplied = false
            var error: NSError?
            let status = converter.convert(to: output, error: &error) { _, outStatus in
                if supplied { outStatus.pointee = .noDataNow; return nil }
                supplied = true; outStatus.pointee = .haveData; return buffer
            }
            if status == .error { failure(error?.localizedDescription ?? "Audio conversion failed."); return }
        } else {
            output.frameLength = buffer.frameLength
            let source = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
            let destination = UnsafeMutableAudioBufferListPointer(output.mutableAudioBufferList)
            for (from, to) in zip(source, destination) {
                if let src = from.mData, let dst = to.mData { memcpy(dst, src, Int(from.mDataByteSize)) }
            }
        }
        if output.frameLength > 0 {
            if case .dropped = continuation.yield(AnalyzerInput(buffer: output)) {
                failure("Transcription couldn't keep up with the microphone. Your draft is preserved; please try again.")
            }
        }
    }
}

@MainActor
final class SpeechRecorder: ObservableObject {
    enum Phase { case idle, preparing, recording, finishing }
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var transcript = ""
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var level: Float = 0
    @Published private(set) var status = "Ready when you are"
    @Published var error: String?
    var isBusy: Bool { phase != .idle }
    var onTranscript: ((String, TimeInterval) -> Void)?
    private var engine: AVAudioEngine?
    private var analyzer: SpeechAnalyzer?
    private var continuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    private var preparationTask: Task<Void, Never>?
    private var timer: Timer?
    private var startedAt: Date?
    private var committed = ""
    private var sessionID = UUID()
    private var configurationObserver: NSObjectProtocol?

    func start(localeID: String) {
        guard phase == .idle else { return }
        phase = .preparing; status = "Preparing your microphone…"; error = nil
        transcript = ""; committed = ""; elapsed = 0; level = 0
        let session = UUID(); sessionID = session
        preparationTask = Task { [self] in
            do {
                guard await AVCaptureDevice.requestAccess(for: .audio) else {
                    throw JournalFailure(message: "Microphone access is off. Enable EasyJournal in System Settings → Privacy & Security → Microphone, then try again.")
                }
                try Task.checkCancellation()
                guard SpeechTranscriber.isAvailable else {
                    throw JournalFailure(message: "On-device transcription isn't available on this Mac. It requires a supported Apple silicon Mac with macOS 26 or later. You can still write an entry below.")
                }
                guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: localeID)) else {
                    throw JournalFailure(message: "On-device transcription doesn't support this language. Choose another language below, or write your entry.")
                }
                let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
                if let installation = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                    status = "Downloading the on-device language model… First use needs internet."
                    try await installation.downloadAndInstall()
                }
                try Task.checkCancellation()
                let engine = AVAudioEngine()
                let input = engine.inputNode
                let source = input.outputFormat(forBus: 0)
                guard source.sampleRate > 0, source.channelCount > 0 else {
                    throw JournalFailure(message: "No microphone is available. Connect one and check System Settings → Sound → Input.")
                }
                guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber], considering: source) else {
                    throw JournalFailure(message: "The speech model isn't ready. Check your internet connection and try again.")
                }
                try Task.checkCancellation()
                let analyzer = SpeechAnalyzer(modules: [transcriber])
                self.analyzer = analyzer
                status = "Getting ready to listen…"
                try await analyzer.prepareToAnalyze(in: format)
                try Task.checkCancellation()
                guard session == sessionID else { return }
                let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream(bufferingPolicy: .bufferingOldest(256))
                self.continuation = continuation
                resultsTask = Task { [weak self] in
                    do {
                        for try await result in transcriber.results {
                            guard let self, self.sessionID == session else { return }
                            let text = String(result.text.characters)
                            if result.isFinal { self.committed += text }
                            self.transcript = self.committed + (result.isFinal ? "" : text)
                            self.onTranscript?(self.transcript, self.elapsed)
                        }
                    } catch {
                        guard let self, self.sessionID == session, !Task.isCancelled else { return }
                        await self.fail("Transcription stopped. Your draft is preserved. \(error.localizedDescription)")
                    }
                }
                try await analyzer.start(inputSequence: stream)
                let bridge = try AudioBridge(source: source, target: format, continuation: continuation,
                    level: { [weak self] value in Task { @MainActor [weak self] in
                        guard let self, self.sessionID == session, self.phase == .recording else { return }
                        self.level = value
                    } }, failure: { [weak self] message in Task { @MainActor [weak self] in
                        guard let self, self.sessionID == session, self.phase == .recording else { return }
                        await self.fail(message)
                    } })
                input.installTap(onBus: 0, bufferSize: 4096, format: source) { buffer, _ in bridge.accept(buffer) }
                self.engine = engine
                engine.prepare()
                try engine.start()
                startedAt = Date(); phase = .recording; status = "Listening. Take your time."
                timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        guard let self, let started = self.startedAt else { return }
                        self.elapsed = Date().timeIntervalSince(started)
                    }
                }
                configurationObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange,
                    object: engine, queue: .main) { [weak self] _ in Task { @MainActor [weak self] in
                        guard let self, self.phase == .recording else { return }
                        await self.fail("Your microphone changed or disconnected. Your draft is preserved; start again to continue.")
                    } }
            } catch {
                guard session == sessionID else { return }
                await fail(error is CancellationError ? "Setup cancelled. You can try again whenever you're ready." : error.localizedDescription)
            }
        }
    }
    func cancelPreparation() async {
        guard phase == .preparing else { return }
        sessionID = UUID(); preparationTask?.cancel()
        await cleanup()
        phase = .idle; status = "Ready when you are"
    }
    /// Ends audio first, then waits for final words before the caller saves the entry.
    func finish() async -> Bool {
        guard phase == .recording else { return false }
        phase = .finishing; status = "Finishing your transcript…"
        stopMicrophone()
        continuation?.finish(); continuation = nil
        do {
            try await analyzer?.finalizeAndFinishThroughEndOfInput()
            await resultsTask?.value
            guard phase == .finishing else { return false }
            onTranscript?(transcript, elapsed)
            await cleanup()
            phase = .idle; status = "Ready when you are"
            return true
        } catch {
            await fail("Couldn't finalize the transcript. Your draft is preserved. \(error.localizedDescription)")
            return false
        }
    }
    private func fail(_ message: String) async {
        onTranscript?(transcript, elapsed)
        error = message
        sessionID = UUID()
        await cleanup()
        phase = .idle; status = "Ready when you are"
    }
    private func stopMicrophone() {
        if let startedAt { elapsed = Date().timeIntervalSince(startedAt) }
        startedAt = nil
        timer?.invalidate(); timer = nil
        if let observer = configurationObserver { NotificationCenter.default.removeObserver(observer); configurationObserver = nil }
        if let engine { engine.stop(); engine.inputNode.removeTap(onBus: 0) }
        engine = nil; level = 0
    }
    private func cleanup() async {
        stopMicrophone()
        continuation?.finish(); continuation = nil
        resultsTask?.cancel(); resultsTask = nil
        await analyzer?.cancelAndFinishNow(); analyzer = nil
    }
}
