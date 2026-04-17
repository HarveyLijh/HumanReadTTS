import Foundation
import AVFoundation
import NaturalLanguage
import Observation

/// Owns an `AVSpeechSynthesizer` and walks through a queue of
/// `Sentence`s one at a time. Picks a voice per sentence via
/// `NLLanguageRecognizer` so a mixed EN/ZH document sounds
/// reasonable even before the Qwen3-TTS bilingual orchestrator
/// lands in Month 3.
///
/// The class is `@MainActor`-isolated so views can observe its
/// state without extra bookkeeping. `AVSpeechSynthesizerDelegate`
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

    private let synth = AVSpeechSynthesizer()
    private let delegate = Delegate()
    private var nextIndex: Int = 0

    init() {
        delegate.player = self
        synth.delegate = delegate
    }

    func load(_ sentences: [Sentence]) {
        synth.stopSpeaking(at: .immediate)
        self.sentences = sentences
        self.nextIndex = 0
        self.state = .idle
    }

    func togglePlayPause() {
        switch state {
        case .idle:
            guard !sentences.isEmpty else { return }
            nextIndex = 0
            speakCurrent()
        case .playing(let i):
            synth.pauseSpeaking(at: .immediate)
            state = .paused(sentenceIndex: i)
        case .paused(let i):
            synth.continueSpeaking()
            state = .playing(sentenceIndex: i)
        }
    }

    func stop() {
        synth.stopSpeaking(at: .immediate)
        state = .idle
        nextIndex = 0
    }

    private func speakCurrent() {
        guard nextIndex < sentences.count else {
            state = .idle
            return
        }
        let sentence = sentences[nextIndex]
        state = .playing(sentenceIndex: nextIndex)

        let utterance = AVSpeechUtterance(string: sentence.text)
        utterance.voice = Self.voice(for: sentence.text)
        synth.speak(utterance)
    }

    // MARK: delegate callbacks (dispatched from main by Delegate)

    fileprivate func didFinishCurrent() {
        nextIndex += 1
        if nextIndex < sentences.count, state.isPlaying {
            speakCurrent()
        } else {
            state = .idle
        }
    }

    fileprivate func didCancel() {
        // Cancellation arrives as a consequence of stop() or load();
        // we've already updated state in those paths.
    }

    // MARK: voice selection

    private static func voice(for text: String) -> AVSpeechSynthesisVoice? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        let lang = recognizer.dominantLanguage?.rawValue
            ?? AVSpeechSynthesisVoice.currentLanguageCode()
        return AVSpeechSynthesisVoice(language: lang)
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
    }
}
