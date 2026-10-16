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
