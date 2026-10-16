import AVFoundation
import Combine
import SwiftUI

@MainActor
final class AudioPlayback: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var playing = false
    @Published var position: Double = 0
    @Published var duration: Double = 0
    @Published var error: String?
    private var player: AVAudioPlayer?
    private var timer: Timer?
    func load(_ url: URL) {
        do {
            player = try AVAudioPlayer(contentsOf: url)
            player?.delegate = self; duration = player?.duration ?? 0
        } catch { self.error = "Recording unavailable. \(error.localizedDescription)" }
    }
    func toggle() {
        guard let player else { return }
        if playing { pause() }
        else {
            if player.currentTime >= player.duration { player.currentTime = 0 }
            playing = player.play()
            if !playing { error = "This recording couldn't be played."; return }
            timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in self?.position = self?.player?.currentTime ?? 0 }
            }
        }
    }
    func seek(_ value: Double) { player?.currentTime = value; position = value }
    func pause() { player?.pause(); playing = false; timer?.invalidate(); timer = nil }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in self?.pause(); self?.position = self?.duration ?? 0 }
    }
}

struct AudioClipView: View {
    let url: URL
    let number: Int
    @StateObject private var playback = AudioPlayback()
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 12) {
                Button { playback.toggle() } label: { Image(systemName: playback.playing ? "pause.fill" : "play.fill").frame(width: 20) }
                    .buttonStyle(.bordered).disabled(playback.duration == 0)
                    .accessibilityLabel(playback.playing ? "Pause recording" : "Play recording \(number)")
                Text("Recording \(number)").font(.system(size: 12))
                Slider(value: Binding(get: { playback.position }, set: playback.seek), in: 0...max(1, playback.duration))
                    .accessibilityLabel("Recording position")
                Text("\(time(playback.position)) / \(time(playback.duration))").font(.system(size: 10)).monospacedDigit().foregroundStyle(.secondary)
            }
            if let error = playback.error { Text(error).font(.caption).foregroundStyle(.secondary) }
        }.onAppear { playback.load(url) }.onDisappear { playback.pause() }
    }
    private func time(_ value: Double) -> String { String(format: "%d:%02d", Int(value) / 60, Int(value) % 60) }
}
