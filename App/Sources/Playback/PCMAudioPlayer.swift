import Foundation
import AVFoundation
import os

/// Plays raw `[Float]` PCM samples via `AVAudioEngine`. One node
/// per player so multiple chunks can be queued back-to-back
/// without scheduling gaps. Used by `SpeechPlayer` to play the
/// audio Kokoro returns from `synthesize(text:voiceID:)`.
///
/// Sample rate is fixed at the engine's input rate at
/// initialisation (the system mixer handles any conversion). The
/// completion callback fires on the main actor when the whole
/// scheduled buffer has finished playing — that's the cue
/// `SpeechPlayer` uses to advance to the next sentence.
@MainActor
final class PCMAudioPlayer {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var inputFormat: AVAudioFormat
    private var isStarted = false

    private static let log = Logger(subsystem: "app.humanreadtts.mac", category: "audio")

    init(sampleRate: Double) {
        self.inputFormat = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: 1
        ) ?? AVAudioFormat(
            standardFormatWithSampleRate: 24_000, channels: 1
        )!
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: inputFormat)
    }

    /// Schedule `samples` for playback and start the engine if it
    /// isn't already running. `onFinish` fires on the main actor
    /// once playback of THIS scheduling completes.
    func play(samples: [Float], onFinish: @escaping @MainActor () -> Void) {
        guard !samples.isEmpty else {
            onFinish()
            return
        }
        guard let buffer = makeBuffer(from: samples) else {
            Self.log.error("could not allocate AVAudioPCMBuffer")
            onFinish()
            return
        }

        startEngineIfNeeded()

        player.scheduleBuffer(buffer, at: nil, options: [], completionCallbackType: .dataPlayedBack) { _ in
            Task { @MainActor in onFinish() }
        }

        if !player.isPlaying {
            player.play()
        }
    }

    func stop() {
        player.stop()
        player.reset()
    }

    // MARK: helpers

    private func startEngineIfNeeded() {
        guard !isStarted else { return }
        do {
            try engine.start()
            isStarted = true
        } catch {
            Self.log.error("AVAudioEngine.start failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func makeBuffer(from samples: [Float]) -> AVAudioPCMBuffer? {
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: inputFormat,
            frameCapacity: AVAudioFrameCount(samples.count)
        ) else { return nil }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        guard let channel = buffer.floatChannelData?.pointee else { return nil }
        samples.withUnsafeBufferPointer { src in
            channel.update(from: src.baseAddress!, count: samples.count)
        }
        return buffer
    }
}
