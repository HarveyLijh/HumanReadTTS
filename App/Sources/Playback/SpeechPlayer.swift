import Foundation
import AVFoundation
import NaturalLanguage
import Observation
import os

/// Owns playback state and walks through a queue of `Sentence`s
/// one at a time. Routes each sentence to one of two engines:
///
/// - **AVSpeechSynthesizer** (default): system voices, EN+ZH out
///   of the box, no model download required.
/// - **KokoroEngine** + **PCMAudioPlayer**: studio-quality English
///   voice via the on-device Kokoro MLX model. Active when the
///   user picks a voice prefixed `kokoro:` in Settings AND the
///   model is downloaded.
///
/// The class is `@MainActor`-isolated so views can observe its
/// state without extra bookkeeping. AVSpeechSynthesizerDelegate
/// callbacks come in on an unspecified thread; a private
/// `Delegate` shim bounces them back to main.
@Observable
@MainActor
final class SpeechPlayer {
    enum PlaybackState: Equatable {
        case idle
        case playing(sentenceIndex: Int)
        case paused(sentenceIndex: Int)

        var sentenceIndex: Int? {
            switch self {
            case .idle: return nil
            case .playing(let i), .paused(let i): return i
            }
        }

        var isPlaying: Bool {
            if case .playing = self { return true }
            return false
        }
    }

    private(set) var state: PlaybackState = .idle

    /// The current sentence queue. Set by `load(_:)` before the
    /// first play so UI can show enabled controls even before
    /// playback starts.
    private(set) var sentences: [Sentence] = []

    /// Sub-range within the currently-playing sentence that the
    /// synthesizer is actively speaking. Driven by
    /// `AVSpeechSynthesizerDelegate.willSpeakRangeOfSpeechString`
    /// for system voices; nil during Kokoro playback.
    private(set) var spokenSubRange: NSRange?

    private let synth = AVSpeechSynthesizer()
    private let delegate = Delegate()
    private let pcm = PCMAudioPlayer(sampleRate: KokoroEngine.sampleRate)
    private var nextIndex: Int = 0
    private var currentEngine: Engine = .system
    private var currentSentenceStartedAt: Date?

    /// Kokoro synth runs per-sentence and each call costs real time,
    /// so we prefetch the next sentence's PCM while the current one
    /// is playing. On sentence advance, a cache hit lets playback
    /// continue with zero gap. Cleared on stop / load / seek.
    private var prefetchedKokoro: [Int: [Float]] = [:]

    private static let log = Logger(subsystem: "app.rhea.mac", category: "playback")

    init() {
        delegate.player = self
        synth.delegate = delegate
    }

    func load(_ sentences: [Sentence]) {
        synth.stopSpeaking(at: .immediate)
        pcm.stop()
        self.sentences = sentences
        self.nextIndex = 0
        self.state = .idle
        self.spokenSubRange = nil
        self.prefetchedKokoro.removeAll()
    }

    func togglePlayPause() {
        switch state {
        case .idle:
            guard !sentences.isEmpty else { return }
            nextIndex = 0
            speakCurrent()
        case .playing(let i):
            switch currentEngine {
            case .system: synth.pauseSpeaking(at: .immediate)
            case .kokoro: pcm.stop()
            }
            state = .paused(sentenceIndex: i)
        case .paused(let i):
            switch currentEngine {
            case .system:
                synth.continueSpeaking()
                state = .playing(sentenceIndex: i)
            case .kokoro:
                // Kokoro can't resume mid-sentence; restart the current.
                state = .playing(sentenceIndex: i)
                speakCurrent()
            }
        }
    }

    func stop() {
        synth.stopSpeaking(at: .immediate)
        pcm.stop()
        state = .idle
        nextIndex = 0
        spokenSubRange = nil
        prefetchedKokoro.removeAll()
    }

    /// Jump to the next sentence. If we're playing, keep playing
    /// from there; if paused/idle, move the cursor but don't start.
    func nextSentence() {
        guard !sentences.isEmpty else { return }
        let target = min((state.sentenceIndex ?? -1) + 1, sentences.count - 1)
        seek(to: target)
    }

    /// Jump to the previous sentence. Same play-or-cursor logic.
    func previousSentence() {
        guard !sentences.isEmpty else { return }
        let target = max((state.sentenceIndex ?? 0) - 1, 0)
        seek(to: target)
    }

    private func seek(to index: Int) {
        let wasPlaying = state.isPlaying
        synth.stopSpeaking(at: .immediate)
        pcm.stop()
        spokenSubRange = nil
        nextIndex = index
        prefetchedKokoro.removeAll()
        if wasPlaying {
            speakCurrent()
        } else {
            state = .paused(sentenceIndex: index)
        }
    }

    private func speakCurrent() {
        guard nextIndex < sentences.count else {
            state = .idle
            return
        }
        let sentence = sentences[nextIndex]
        state = .playing(sentenceIndex: nextIndex)
        currentSentenceStartedAt = Date()

        let settings = SpeechSettings.shared
        let voiceID = settings.voiceIdentifier ?? ""

        if voiceID.hasPrefix("kokoro:") {
            currentEngine = .kokoro
            speakWithKokoro(sentence: sentence, voiceID: String(voiceID.dropFirst("kokoro:".count)), settings: settings)
        } else {
            currentEngine = .system
            speakWithSystem(sentence: sentence, settings: settings)
        }
    }

    private func speakWithSystem(sentence: Sentence, settings: SpeechSettings) {
        var spokenText = PronunciationDictionary.shared.apply(to: sentence.text)
        spokenText = ResearchCleanup.clean(spokenText, stripCitations: settings.stripCitations)
        let utterance = AVSpeechUtterance(string: spokenText)
        utterance.voice = Self.systemVoice(for: sentence.text, settings: settings)
        utterance.rate = settings.avSpeechRate
        utterance.pitchMultiplier = Float(settings.pitchMultiplier)
        synth.speak(utterance)
    }

    private func speakWithKokoro(sentence: Sentence, voiceID: String, settings: SpeechSettings) {
        let speed = Float(settings.rate)
        let myIndex = nextIndex

        // Cache hit: pre-buffered during the previous sentence.
        if let samples = prefetchedKokoro.removeValue(forKey: myIndex) {
            pcm.play(samples: samples) { [weak self] in
                self?.didFinishCurrent()
            }
            prefetchKokoro(after: myIndex, voiceID: voiceID, settings: settings)
            return
        }

        var spokenText = PronunciationDictionary.shared.apply(to: sentence.text)
        spokenText = ResearchCleanup.clean(spokenText, stripCitations: settings.stripCitations)
        Task { @MainActor [weak self] in
            guard let self else { return }
            await KokoroEngine.shared.loadIfNeeded()
            do {
                let samples = try await KokoroEngine.shared.synthesize(
                    text: spokenText, voiceID: voiceID, speed: speed
                )
                // The user may have skipped or stopped while we were
                // synthesising. Only play if we're still on the same
                // sentence and still in playing state.
                guard self.state.sentenceIndex == myIndex,
                      case .playing = self.state else { return }
                self.pcm.play(samples: samples) { [weak self] in
                    self?.didFinishCurrent()
                }
                self.prefetchKokoro(after: myIndex, voiceID: voiceID, settings: settings)
            } catch {
                Self.log.error("Kokoro synth failed: \(error.localizedDescription, privacy: .public). Falling back to system voice.")
                // Fall back so the user still gets audio.
                self.currentEngine = .system
                self.speakWithSystem(sentence: sentence, settings: settings)
            }
        }
    }

    /// Fire-and-forget: synthesise the sentence after `playingIndex`
    /// while the user listens to `playingIndex`, then stash the PCM
    /// so the next `speakWithKokoro` hits the cache. Silent on error
    /// — the main path will retry when it reaches that sentence.
    private func prefetchKokoro(after playingIndex: Int, voiceID: String, settings: SpeechSettings) {
        let nextIdx = playingIndex + 1
        guard nextIdx < sentences.count,
              prefetchedKokoro[nextIdx] == nil else { return }
        let sentence = sentences[nextIdx]
        let speed = Float(settings.rate)
        var spokenText = PronunciationDictionary.shared.apply(to: sentence.text)
        spokenText = ResearchCleanup.clean(spokenText, stripCitations: settings.stripCitations)
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let samples = try await KokoroEngine.shared.synthesize(
                    text: spokenText, voiceID: voiceID, speed: speed
                )
                // Drop prefetch if the user skipped/stopped during synth.
                guard nextIdx == self.nextIndex + 1 else { return }
                self.prefetchedKokoro[nextIdx] = samples
            } catch {
                // Silent; main-path synth will surface the error.
            }
        }
    }

    // MARK: delegate callbacks (dispatched from main by Delegate)

    fileprivate func didFinishCurrent() {
        recordSentenceForStats()
        spokenSubRange = nil
        nextIndex += 1
        if nextIndex < sentences.count, state.isPlaying {
            speakCurrent()
        } else {
            state = .idle
        }
    }

    private func recordSentenceForStats() {
        guard let startedAt = currentSentenceStartedAt,
              let currentIndex = state.sentenceIndex,
              currentIndex < sentences.count else { return }
        let duration = Date().timeIntervalSince(startedAt)
        let text = sentences[currentIndex].text
        ReadingStats.shared.recordSentence(
            wordCount: text.roughWordCount,
            duration: duration
        )
        currentSentenceStartedAt = nil
    }

    fileprivate func didCancel() {
        // Cancellation arrives as a consequence of stop() or load();
        // we've already updated state in those paths.
        spokenSubRange = nil
    }

    fileprivate func updateSpokenSubRange(_ range: NSRange) {
        spokenSubRange = range
    }

    // MARK: voice selection

    /// Resolves a system `AVSpeechSynthesisVoice`. If the user
    /// pinned a system voice in Settings, use it; otherwise fall
    /// back to per-sentence language detection (the bilingual
    /// default).
    private static func systemVoice(for text: String, settings: SpeechSettings) -> AVSpeechSynthesisVoice? {
        if let id = settings.voiceIdentifier,
           !id.hasPrefix("kokoro:"),
           let voice = AVSpeechSynthesisVoice(identifier: id) {
            return voice
        }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        let lang = recognizer.dominantLanguage?.rawValue
            ?? AVSpeechSynthesisVoice.currentLanguageCode()
        return AVSpeechSynthesisVoice(language: lang)
    }

    // MARK: types

    private enum Engine {
        case system
        case kokoro
    }

    // MARK: delegate

    private final class Delegate: NSObject, AVSpeechSynthesizerDelegate {
        // The back-reference is set once during SpeechPlayer.init on
        // the main actor; Strict Concurrency needs `nonisolated(unsafe)`
        // because NSObject delegates are visible across threads.
        nonisolated(unsafe) weak var player: SpeechPlayer?

        nonisolated func speechSynthesizer(
            _ synthesizer: AVSpeechSynthesizer,
            didFinish utterance: AVSpeechUtterance
        ) {
            Task { @MainActor [weak self] in self?.player?.didFinishCurrent() }
        }

        nonisolated func speechSynthesizer(
            _ synthesizer: AVSpeechSynthesizer,
            didCancel utterance: AVSpeechUtterance
        ) {
            Task { @MainActor [weak self] in self?.player?.didCancel() }
        }

        nonisolated func speechSynthesizer(
            _ synthesizer: AVSpeechSynthesizer,
            willSpeakRangeOfSpeechString characterRange: NSRange,
            utterance: AVSpeechUtterance
        ) {
            Task { @MainActor [weak self] in
                self?.player?.updateSpokenSubRange(characterRange)
            }
        }
    }
}
