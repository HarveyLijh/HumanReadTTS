import Foundation
import AVFoundation
import NaturalLanguage
import os

// AVSpeechSynthesizer + AVAudioPCMBuffer aren't formally Sendable,
// but the exporter owns them on a single actor and hands them
// across boundaries only in well-defined hand-offs (write callback
// → continuation). Region-isolation-safe; mark unchecked Sendable.
extension AVSpeechSynthesizer: @unchecked @retroactive Sendable {}
extension AVAudioPCMBuffer: @unchecked @retroactive Sendable {}

/// Renders the current sentence queue to an AAC-encoded `.m4a`
/// file via `AVAudioFile`. Runs sequentially: synth sentence → PCM
/// buffer → append → next. Progress is reported on the main
/// actor as fraction 0.0 – 1.0.
///
/// Routes each sentence through the same engine the SpeechPlayer
/// would use live — Kokoro when the user has picked a `kokoro:`
/// voice, AVSpeechSynthesizer otherwise.
///
/// Chapter markers (per document block) are a follow-up; v1 is
/// single-track audio only. The caller can rename the resulting
/// `.m4a` to `.m4b` for audiobook convention; both are AAC/MP4.
@MainActor
enum AudioExporter {
    enum ExportError: LocalizedError {
        case emptyQueue
        case voiceMissing
        case writerSetupFailed(String)
        case synthesisFailed(String)

        var errorDescription: String? {
            switch self {
            case .emptyQueue: return "Nothing to export — load a document first."
            case .voiceMissing: return "Couldn't find a usable voice for export."
            case .writerSetupFailed(let m): return "Couldn't open output file: \(m)"
            case .synthesisFailed(let m): return "Synthesis failed: \(m)"
            }
        }
    }

    private static let log = Logger(subsystem: "app.rhea.mac", category: "export")

    /// Export `sentences` to `destination` in `format`. `progress`
    /// is called on the main actor with fraction of sentences
    /// completed.
    static func export(
        sentences: [Sentence],
        to destination: URL,
        format: AudioExportFormat = .m4a,
        progress: @escaping @MainActor (Double) -> Void = { _ in }
    ) async throws {
        guard !sentences.isEmpty else { throw ExportError.emptyQueue }

        let settings = SpeechSettings.shared
        let voiceID = settings.voiceIdentifier ?? ""
        let useKokoro = voiceID.hasPrefix("kokoro:")
        let useQwen = voiceID.hasPrefix("qwen:")
        let kokoroVoice = useKokoro ? String(voiceID.dropFirst("kokoro:".count)) : nil
        let qwenVoice = useQwen ? String(voiceID.dropFirst("qwen:".count)) : nil

        // Sample rate: 24 kHz for the neural paths (both Kokoro and
        // Qwen3-TTS output at 24k), 22.05 kHz for the system path
        // (AVSpeechSynthesizer's native output rate on most voices).
        // One rate per export so the AVAudioFile can stay simple.
        let sampleRate: Double = (useKokoro || useQwen) ? 24_000 : 22_050
        let fileSettings = format.avSettings(sampleRate: sampleRate)

        let pcmFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        )!

        // Make sure we can overwrite an existing file.
        try? FileManager.default.removeItem(at: destination)

        let file: AVAudioFile
        do {
            file = try AVAudioFile(
                forWriting: destination,
                settings: fileSettings,
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )
        } catch {
            throw ExportError.writerSetupFailed(error.localizedDescription)
        }

        let total = sentences.count
        Self.log.info("export begin: \(total) sentences → \(destination.path, privacy: .public) rate=\(sampleRate)")

        for (index, sentence) in sentences.enumerated() {
            var spokenText = PronunciationDictionary.shared.apply(to: sentence.text)
            spokenText = ResearchCleanup.clean(spokenText, stripCitations: settings.stripCitations, skipRules: settings.skipRules)

            let buffer: AVAudioPCMBuffer
            do {
                if useKokoro, let kokoroVoice {
                    let samples = try await synthesizeWithKokoro(
                        text: spokenText, voiceID: kokoroVoice, speed: Float(settings.rate)
                    )
                    buffer = try makeBuffer(samples: samples, format: pcmFormat)
                } else if useQwen, let qwenVoice {
                    let samples = try await synthesizeWithQwen(
                        text: spokenText,
                        voiceID: qwenVoice,
                        language: Self.languageCode(for: sentence.text),
                        speed: Float(settings.rate)
                    )
                    buffer = try makeBuffer(samples: samples, format: pcmFormat)
                } else {
                    buffer = try await synthesizeWithSystem(
                        text: spokenText, settings: settings, format: pcmFormat
                    )
                }
            } catch let error as ExportError {
                throw error
            } catch {
                throw ExportError.synthesisFailed(error.localizedDescription)
            }

            try file.write(from: buffer)
            let completed = Double(index + 1) / Double(total)
            progress(completed)
        }

        Self.log.info("export complete")
    }

    // MARK: Kokoro path

    private static func synthesizeWithKokoro(
        text: String, voiceID: String, speed: Float
    ) async throws -> [Float] {
        await KokoroEngine.shared.loadIfNeeded()
        do {
            return try await KokoroEngine.shared.synthesize(
                text: text, voiceID: voiceID, speed: speed
            )
        } catch {
            throw ExportError.synthesisFailed(error.localizedDescription)
        }
    }

    // MARK: Qwen path

    private static func synthesizeWithQwen(
        text: String, voiceID: String, language: String, speed: Float
    ) async throws -> [Float] {
        await QwenEngine.shared.loadIfNeeded()
        do {
            return try await QwenEngine.shared.synthesize(
                text: text, voiceID: voiceID, language: language, speed: speed
            )
        } catch {
            throw ExportError.synthesisFailed(error.localizedDescription)
        }
    }

    private static func languageCode(for text: String) -> String {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage?.rawValue ?? "en"
    }

    // MARK: System voice path

    /// Uses `AVSpeechSynthesizer.write(_:toBufferCallback:)`, the
    /// supported path for pulling PCM out of a synthesizer without
    /// playing it through the speakers. Collects all partial
    /// buffers into one continuous Float32 buffer at `format`.
    private static func synthesizeWithSystem(
        text: String, settings: SpeechSettings, format: AVAudioFormat
    ) async throws -> AVAudioPCMBuffer {
        let synth = AVSpeechSynthesizer()

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = resolveSystemVoice(for: text, settings: settings)
        utterance.rate = settings.avSpeechRate
        utterance.pitchMultiplier = Float(settings.pitchMultiplier)

        return try await withCheckedThrowingContinuation { cont in
            var collected: [Float] = []
            synth.write(utterance) { buffer in
                guard let pcm = buffer as? AVAudioPCMBuffer else { return }
                // Completion sentinel: framework delivers a zero-frame
                // buffer once the utterance is done.
                if pcm.frameLength == 0 {
                    do {
                        let out = try Self.makeBuffer(samples: collected, format: format)
                        cont.resume(returning: out)
                    } catch {
                        cont.resume(throwing: error)
                    }
                    return
                }
                let resampled = Self.resampleToMono(pcm, targetRate: format.sampleRate)
                collected.append(contentsOf: resampled)
            }
        }
    }

    private static func resolveSystemVoice(
        for text: String, settings: SpeechSettings
    ) -> AVSpeechSynthesisVoice? {
        if let id = settings.voiceIdentifier,
           !id.hasPrefix("kokoro:"),
           let v = AVSpeechSynthesisVoice(identifier: id) {
            return v
        }
        return AVSpeechSynthesisVoice(language: AVSpeechSynthesisVoice.currentLanguageCode())
    }

    /// Naive resample / mono-mix for system-voice buffers. System
    /// voices deliver at a fixed rate (typically 22050 Hz mono),
    /// and our target is the same for system exports, so this is
    /// a straight copy in the common case. For the odd case where
    /// rates differ we do a cheap nearest-neighbour resample — ok
    /// for speech which is fricative-heavy and forgiving.
    private static func resampleToMono(
        _ pcm: AVAudioPCMBuffer, targetRate: Double
    ) -> [Float] {
        guard let src = pcm.floatChannelData else { return [] }
        let channels = Int(pcm.format.channelCount)
        let frameCount = Int(pcm.frameLength)
        let srcRate = pcm.format.sampleRate

        // Mix down to mono first.
        var mono = [Float](repeating: 0, count: frameCount)
        for ch in 0..<channels {
            let ptr = src[ch]
            for i in 0..<frameCount {
                mono[i] += ptr[i]
            }
        }
        if channels > 1 {
            let inv = 1.0 / Float(channels)
            for i in 0..<frameCount { mono[i] *= inv }
        }

        // Resample if needed.
        if abs(srcRate - targetRate) < 0.5 { return mono }
        let ratio = targetRate / srcRate
        let outCount = Int((Double(frameCount) * ratio).rounded())
        var out = [Float](repeating: 0, count: outCount)
        for i in 0..<outCount {
            let srcIdx = Int((Double(i) / ratio).rounded())
            out[i] = mono[min(srcIdx, frameCount - 1)]
        }
        return out
    }

    // MARK: buffer helpers

    private static func makeBuffer(samples: [Float], format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format, frameCapacity: AVAudioFrameCount(max(samples.count, 1))
        ) else {
            throw ExportError.writerSetupFailed("could not allocate PCM buffer")
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        guard let channel = buffer.floatChannelData?.pointee else {
            throw ExportError.writerSetupFailed("PCM buffer has no float channel data")
        }
        samples.withUnsafeBufferPointer { src in
            channel.update(from: src.baseAddress!, count: samples.count)
        }
        return buffer
    }
}
