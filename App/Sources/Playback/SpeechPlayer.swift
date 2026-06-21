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

    /// One-shot record of the last mid-playback switch. UI reads this
    /// to show an undo toast. Cleared when the user dismisses the
    /// toast or a new switch event arrives. Observers see the
    /// transition via `@Observable`.
    struct SwitchEvent: Equatable {
        enum Kind: Equatable {
            case voiceChanged(previous: String?, current: String?)
            /// Neural engine selected by the user couldn't synthesize
            /// (model file missing / corrupt / still downloading) and
            /// we silently fell back to a system voice. The banner
            /// the UI shows from this event is the user's first sign
            /// that the voice they picked is unusable.
            case engineFallback(requested: String, reason: String)
        }
        let kind: Kind
        let sentenceIndex: Int
        let timestamp: Date
    }

    private(set) var state: PlaybackState = .idle
    private(set) var lastSwitchEvent: SwitchEvent?

    /// When set, the player pauses at the next sentence boundary
    /// instead of advancing — the current sentence finishes speaking,
    /// then playback stops in place. Used by the sleep timer's
    /// "end of current sentence" mode. Cleared once honored.
    var stopAtNextSentenceBoundary: Bool = false

    /// Fired once the last sentence finishes by natural playback (not a
    /// user `stop()`), after `state` has gone `.idle`. The reading queue
    /// uses it to auto-advance to the next item; if the handler starts a
    /// new read it overrides the idle state. Nil = nothing queued.
    var onReachedEnd: (() -> Void)?

    /// The current sentence queue. Set by `load(_:)` before the
    /// first play so UI can show enabled controls even before
    /// playback starts.
    private(set) var sentences: [Sentence] = []

    /// Prefix-sum of word counts so `progress` can answer elapsed /
    /// remaining in O(1). Without this the scrubber recomputes two
    /// `reduce` walks of up to several thousand sentences on every
    /// drag tick, which pegs the main thread during a seek.
    /// `prefixWordCounts[i]` is the total words in `sentences[0..<i]`;
    /// length is `sentences.count + 1`.
    private var prefixWordCounts: [Int] = [0]

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

    /// Neural-TTS prefetch cache. Kokoro and Qwen3-TTS both cost
    /// real time per sentence, so while sentence N plays we
    /// synthesise N+1 in the background and stash the PCM here.
    /// On sentence advance, a cache hit means zero gap. Cleared on
    /// stop / load / seek to avoid replaying a skipped sentence.
    private var prefetchedKokoro: [Int: [Float]] = [:]
    private var prefetchedQwen: [Int: [Float]] = [:]

    /// Word-level highlight alignment task for the current neural
    /// sentence. Cancelled on stop / load / seek; the task itself
    /// also bails out if `state.sentenceIndex` changes during its
    /// run, so a fast skip can't trigger a stale word update on
    /// the next sentence.
    private var alignmentTask: Task<Void, Never>?

    private static let log = Logger(subsystem: "app.readaloudtts.mac", category: "playback")

    init() {
        delegate.player = self
        synth.delegate = delegate
    }

    func load(_ sentences: [Sentence]) {
        synth.stopSpeaking(at: .immediate)
        pcm.stop()
        self.sentences = sentences
        self.prefixWordCounts = Self.buildPrefixWordCounts(for: sentences)
        self.nextIndex = 0
        self.state = .idle
        self.spokenSubRange = nil
        self.stopAtNextSentenceBoundary = false
        self.prefetchedKokoro.removeAll()
        self.prefetchedQwen.removeAll()
        self.alignmentTask?.cancel()
        self.alignmentTask = nil
        self.lastSwitchEvent = nil
    }

    private static func buildPrefixWordCounts(for sentences: [Sentence]) -> [Int] {
        var prefix = [Int](repeating: 0, count: sentences.count + 1)
        var running = 0
        for (i, s) in sentences.enumerated() {
            running += s.text.roughWordCount
            prefix[i + 1] = running
        }
        return prefix
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
            case .kokoro, .qwen: pcm.stop()
            }
            state = .paused(sentenceIndex: i)
        case .paused(let i):
            switch currentEngine {
            case .system:
                synth.continueSpeaking()
                state = .playing(sentenceIndex: i)
            case .kokoro, .qwen:
                // Neural engines can't resume mid-sentence; restart current.
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
        prefetchedQwen.removeAll()
        alignmentTask?.cancel()
        alignmentTask = nil
        // Hand MLX's cached synthesis buffers back to the OS now that
        // playback is over, so resident memory drops instead of sitting
        // at the reading high-water mark for the rest of the session.
        KokoroEngine.shared.releaseCache()
    }

    /// Seek to `index` but stay paused. Used to restore the user's
    /// last reading position when they reopen a document — they
    /// see the prior sentence highlighted and the transport paused,
    /// then press space or the play button to resume. Auto-playing
    /// a document the user hasn't touched in a session would be
    /// surprising and violate the "transparency of side effects"
    /// rule.
    func seekPaused(to index: Int) {
        guard !sentences.isEmpty else { return }
        let clamped = max(0, min(index, sentences.count - 1))
        synth.stopSpeaking(at: .immediate)
        pcm.stop()
        spokenSubRange = nil
        prefetchedKokoro.removeAll()
        prefetchedQwen.removeAll()
        alignmentTask?.cancel()
        alignmentTask = nil
        nextIndex = clamped
        state = .paused(sentenceIndex: clamped)
    }

    /// Public seek-and-play. If the player is idle, transitions to
    /// playing at `index`. If paused, starts playing at `index`. If
    /// already playing, moves to `index` and keeps playing. Used by
    /// the transport scrubber (on release) and the
    /// click-to-start-from-word handlers.
    func playFromSentence(_ index: Int) {
        guard !sentences.isEmpty else { return }
        let clamped = max(0, min(index, sentences.count - 1))
        synth.stopSpeaking(at: .immediate)
        pcm.stop()
        spokenSubRange = nil
        prefetchedKokoro.removeAll()
        prefetchedQwen.removeAll()
        alignmentTask?.cancel()
        alignmentTask = nil
        nextIndex = clamped
        speakCurrent()
    }

    /// Live voice switch. Persists the new identifier to settings
    /// and, if we're mid-playback, stops the current engine, clears
    /// prefetch caches (which hold the *previous* voice's PCM and
    /// would otherwise replay with the old voice), and restarts the
    /// current sentence on the new engine. Emits a `SwitchEvent` so
    /// the UI can surface an undo toast. No-op when the identifier
    /// is unchanged.
    func setVoice(_ identifier: String?) {
        let settings = SpeechSettings.shared
        let previous = settings.voiceIdentifier
        guard previous != identifier else { return }
        settings.voiceIdentifier = identifier
        Self.unloadEngines(notNeededBy: identifier)

        guard let index = state.sentenceIndex else {
            // Idle — no sentence to restart; persisted value will be
            // picked up on next play.
            lastSwitchEvent = SwitchEvent(
                kind: .voiceChanged(previous: previous, current: identifier),
                sentenceIndex: -1,
                timestamp: Date()
            )
            return
        }

        let wasPlaying = state.isPlaying
        synth.stopSpeaking(at: .immediate)
        pcm.stop()
        spokenSubRange = nil
        prefetchedKokoro.removeAll()
        prefetchedQwen.removeAll()
        alignmentTask?.cancel()
        alignmentTask = nil
        nextIndex = index
        lastSwitchEvent = SwitchEvent(
            kind: .voiceChanged(previous: previous, current: identifier),
            sentenceIndex: index,
            timestamp: Date()
        )
        if wasPlaying {
            speakCurrent()
        } else {
            state = .paused(sentenceIndex: index)
        }
    }

    /// Dismiss the one-shot switch event. Called by the toast when
    /// the user taps the × or the 3-second auto-timer fires.
    func dismissSwitchEvent() {
        lastSwitchEvent = nil
    }

    /// Drop the prefetched PCM for the next neural sentence so a
    /// mid-playback settings change (skip rules toggled, pronunciation
    /// dictionary edited) takes effect at the next sentence. Without
    /// this the prefetched next-sentence sample, synthesized against
    /// the previous text, would play verbatim and hide the user's
    /// change until they skip or restart. Safe to call any time —
    /// it's a cache drop, not a state transition.
    func invalidateNeuralPrefetch() {
        prefetchedKokoro.removeAll()
        prefetchedQwen.removeAll()
    }

    /// Neural engines (Kokoro/Qwen) call this after a successful
    /// synthesis so a previously-stuck "System (fallback)" chip
    /// heals as soon as the user's chosen voice works again
    /// — e.g. they re-downloaded the model. Only clears when the
    /// live event is a stale `.engineFallback`; voice-change events
    /// still auto-dismiss via the banner timer.
    fileprivate func clearFallbackEventIfStale() {
        guard let event = lastSwitchEvent,
              case .engineFallback = event.kind else { return }
        lastSwitchEvent = nil
    }

    /// Live speed change. Persists to settings; takes effect at the
    /// next sentence boundary for all engines (AVSpeechUtterance is
    /// immutable mid-utterance, and neural engines synthesise per
    /// sentence). The current sentence finishes at the old rate.
    func setRate(_ rate: Double) {
        SpeechSettings.shared.rate = rate
    }

    // MARK: progress readout

    struct Progress: Equatable {
        let currentIndex: Int
        let total: Int
        let fraction: Double
        let estimatedElapsed: TimeInterval
        let estimatedRemaining: TimeInterval
    }

    /// Estimated progress over the current sentence queue. Uses
    /// `ReadingStats.wordsPerMinute` when available (enabled and
    /// populated); falls back to 165 wpm × current rate. Treats
    /// the reading position as "N sentences completed" so idle and
    /// paused both return the cursor's index.
    var progress: Progress {
        let total = sentences.count
        guard total > 0 else {
            return Progress(
                currentIndex: 0, total: 0, fraction: 0,
                estimatedElapsed: 0, estimatedRemaining: 0
            )
        }
        let index = max(0, min(state.sentenceIndex ?? 0, total - 1))
        let rate = SpeechSettings.shared.rate
        let statsWpm = ReadingStats.shared.wordsPerMinute
        let baseWpm = statsWpm > 0 ? statsWpm : 165.0
        let wpm = baseWpm * rate
        let secondsPerWord = 60.0 / max(wpm, 1)
        // O(1) lookups using the cached prefix sum. Previously this
        // did two `reduce` walks of up to several thousand sentences
        // on every call — a scrubber drag fired it every frame, which
        // was the cause of the reported lag.
        let totalWords = prefixWordCounts.last ?? 0
        let elapsedWords = prefixWordCounts.indices.contains(index)
            ? prefixWordCounts[index] : 0
        let remainingWords = max(totalWords - elapsedWords, 0)
        let elapsed = Double(elapsedWords) * secondsPerWord
        let remaining = Double(remainingWords) * secondsPerWord
        let fraction = total <= 1 ? 0 : Double(index) / Double(total - 1)
        return Progress(
            currentIndex: index, total: total, fraction: fraction,
            estimatedElapsed: elapsed, estimatedRemaining: remaining
        )
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
        prefetchedQwen.removeAll()
        alignmentTask?.cancel()
        alignmentTask = nil
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
            speakWithKokoro(
                sentence: sentence,
                voiceID: String(voiceID.dropFirst("kokoro:".count)),
                settings: settings
            )
        } else if voiceID.hasPrefix("qwen:") {
            currentEngine = .qwen
            speakWithQwen(
                sentence: sentence,
                voiceID: String(voiceID.dropFirst("qwen:".count)),
                settings: settings
            )
        } else {
            currentEngine = .system
            speakWithSystem(sentence: sentence, settings: settings)
        }
    }

    private func speakWithSystem(sentence: Sentence, settings: SpeechSettings) {
        var spokenText = PronunciationDictionary.shared.apply(to: sentence.text)
        spokenText = ResearchCleanup.clean(spokenText, stripCitations: settings.stripCitations, skipRules: settings.skipRules)
        let utterance = AVSpeechUtterance(string: spokenText)
        utterance.voice = Self.systemVoice(for: sentence.text, settings: settings)
        utterance.rate = settings.avSpeechRate
        utterance.pitchMultiplier = Float(settings.pitchMultiplier)
        synth.speak(utterance)
    }

    private func speakWithKokoro(sentence: Sentence, voiceID: String, settings: SpeechSettings) {
        let speed = Float(settings.rate)
        let myIndex = nextIndex
        let expectedVoiceID = "kokoro:" + voiceID

        // Cache hit: pre-buffered during the previous sentence.
        if let samples = prefetchedKokoro.removeValue(forKey: myIndex) {
            let start = ContinuousClock.now
            pcm.play(samples: samples) { [weak self] in
                self?.didFinishCurrent()
            }
            startWordAlignment(
                samples: samples, text: sentence.text,
                sentenceIndex: myIndex,
                sampleRate: KokoroEngine.sampleRate,
                playbackStart: start
            )
            prefetchKokoro(after: myIndex, voiceID: voiceID, settings: settings)
            return
        }

        var spokenText = PronunciationDictionary.shared.apply(to: sentence.text)
        spokenText = ResearchCleanup.clean(spokenText, stripCitations: settings.stripCitations, skipRules: settings.skipRules)
        Task { @MainActor [weak self] in
            guard let self else { return }
            await KokoroEngine.shared.loadIfNeeded()

            // Streaming path: schedule each chunk's audio as it lands
            // so the user starts hearing chunk 1 while chunks 2+ are
            // still being synthesised. AVAudioPlayerNode plays
            // scheduled buffers in order with no inter-buffer gap.
            //
            // We track end-of-stream via a trailing zero-frame
            // sentinel buffer whose `dataPlayedBack` callback fires
            // after the last real chunk has finished playing — that's
            // what advances to the next sentence.
            let stream = KokoroEngine.shared.synthesizeStream(
                text: spokenText, voiceID: voiceID, speed: speed
            )
            let interChunkSilence = [Float](
                repeating: 0, count: KokoroChunker.interChunkSilenceFrames
            )
            var collected: [Float] = []
            var startedPlaying = false
            var playbackStart = ContinuousClock.now
            var sawAnyChunk = false

            do {
                for try await chunk in stream {
                    // Re-check user state on every chunk: a skip/stop
                    // or voice swap mid-stream means we should bail
                    // before scheduling stale audio for playback.
                    guard self.state.sentenceIndex == myIndex,
                          case .playing = self.state,
                          SpeechSettings.shared.voiceIdentifier == expectedVoiceID else {
                        return
                    }
                    if !startedPlaying {
                        playbackStart = ContinuousClock.now
                        startedPlaying = true
                    } else {
                        // Slight silence between chunks so the vocoder
                        // re-entry doesn't click and prosody phrasing
                        // gets a natural pause at the seam.
                        self.pcm.play(samples: interChunkSilence) { }
                    }
                    self.pcm.play(samples: chunk) { }
                    collected.append(contentsOf: chunk)
                    sawAnyChunk = true
                }
            } catch {
                Self.log.error("Kokoro synth failed: \(error.localizedDescription, privacy: .public). Falling back to system voice.")
                self.lastSwitchEvent = SwitchEvent(
                    kind: .engineFallback(
                        requested: "Kokoro",
                        reason: error.localizedDescription
                    ),
                    sentenceIndex: self.state.sentenceIndex ?? -1,
                    timestamp: Date()
                )
                self.currentEngine = .system
                self.speakWithSystem(sentence: sentence, settings: settings)
                return
            }

            guard sawAnyChunk else { return }
            // Confirm we still own this sentence before scheduling
            // the sentinel and starting alignment.
            guard self.state.sentenceIndex == myIndex,
                  case .playing = self.state,
                  SpeechSettings.shared.voiceIdentifier == expectedVoiceID else { return }

            // Sentinel: a tiny silent buffer scheduled AFTER the last
            // real chunk. AVAudioPlayerNode plays it last, and its
            // completion callback advances to the next sentence.
            let sentinel = [Float](repeating: 0, count: 240) // 10 ms @ 24 kHz
            self.pcm.play(samples: sentinel) { [weak self] in
                self?.didFinishCurrent()
            }

            self.startWordAlignment(
                samples: collected, text: sentence.text,
                sentenceIndex: myIndex,
                sampleRate: KokoroEngine.sampleRate,
                playbackStart: playbackStart
            )
            self.clearFallbackEventIfStale()
            self.prefetchKokoro(after: myIndex, voiceID: voiceID, settings: settings)
        }
    }

    private func speakWithQwen(sentence: Sentence, voiceID: String, settings: SpeechSettings) {
        let speed = Float(settings.rate)
        let myIndex = nextIndex
        let expectedVoiceID = "qwen:" + voiceID

        if let samples = prefetchedQwen.removeValue(forKey: myIndex) {
            let start = ContinuousClock.now
            pcm.play(samples: samples) { [weak self] in
                self?.didFinishCurrent()
            }
            startWordAlignment(
                samples: samples, text: sentence.text,
                sentenceIndex: myIndex,
                sampleRate: QwenEngine.sampleRate,
                playbackStart: start
            )
            prefetchQwen(after: myIndex, voiceID: voiceID, settings: settings)
            return
        }

        var spokenText = PronunciationDictionary.shared.apply(to: sentence.text)
        spokenText = ResearchCleanup.clean(spokenText, stripCitations: settings.stripCitations, skipRules: settings.skipRules)
        let language = Self.languageCode(for: sentence.text)
        Task { @MainActor [weak self] in
            guard let self else { return }
            await QwenEngine.shared.loadIfNeeded()
            do {
                let samples = try await QwenEngine.shared.synthesize(
                    text: spokenText, voiceID: voiceID, language: language, speed: speed
                )
                guard self.state.sentenceIndex == myIndex,
                      case .playing = self.state,
                      SpeechSettings.shared.voiceIdentifier == expectedVoiceID else { return }
                let start = ContinuousClock.now
                self.pcm.play(samples: samples) { [weak self] in
                    self?.didFinishCurrent()
                }
                self.startWordAlignment(
                    samples: samples, text: sentence.text,
                    sentenceIndex: myIndex,
                    sampleRate: QwenEngine.sampleRate,
                    playbackStart: start
                )
                self.clearFallbackEventIfStale()
                self.prefetchQwen(after: myIndex, voiceID: voiceID, settings: settings)
            } catch {
                Self.log.error("Qwen synth failed: \(error.localizedDescription, privacy: .public). Falling back to system voice.")
                self.lastSwitchEvent = SwitchEvent(
                    kind: .engineFallback(
                        requested: "Qwen3-TTS",
                        reason: error.localizedDescription
                    ),
                    sentenceIndex: self.state.sentenceIndex ?? -1,
                    timestamp: Date()
                )
                self.currentEngine = .system
                self.speakWithSystem(sentence: sentence, settings: settings)
            }
        }
    }

    /// Kick off a background Whisper alignment pass and advance
    /// `spokenSubRange` on each returned word's scheduled start.
    /// No-op when Whisper isn't installed — the caller shouldn't
    /// need to check first. Cancels any previous alignment task.
    private func startWordAlignment(
        samples: [Float],
        text: String,
        sentenceIndex: Int,
        sampleRate: Double,
        playbackStart: ContinuousClock.Instant
    ) {
        alignmentTask?.cancel()
        alignmentTask = Task { @MainActor [weak self] in
            guard let self else { return }
            guard let words = await WhisperAligner.shared.align(
                samples: samples, text: text, sampleRate: sampleRate
            ) else { return }
            guard !Task.isCancelled,
                  case .playing(let current) = self.state,
                  current == sentenceIndex else { return }
            for word in words {
                let target = playbackStart.advanced(
                    by: .milliseconds(Int((word.startSeconds * 1000).rounded()))
                )
                if ContinuousClock.now < target {
                    try? await Task.sleep(until: target, clock: .continuous)
                }
                // Bail if the user paused or skipped: the task's
                // wall-clock timeline is decoupled from the audio
                // player, so without this guard word highlights keep
                // ticking through the rest of the sentence after
                // `pcm.stop()` silences the audio.
                guard !Task.isCancelled,
                      case .playing(let stillCurrent) = self.state,
                      stillCurrent == sentenceIndex else { return }
                self.spokenSubRange = word.characterRange
            }
        }
    }

    private func prefetchQwen(after playingIndex: Int, voiceID: String, settings: SpeechSettings) {
        let nextIdx = playingIndex + 1
        guard nextIdx < sentences.count,
              prefetchedQwen[nextIdx] == nil else { return }
        let sentence = sentences[nextIdx]
        let speed = Float(settings.rate)
        var spokenText = PronunciationDictionary.shared.apply(to: sentence.text)
        spokenText = ResearchCleanup.clean(spokenText, stripCitations: settings.stripCitations, skipRules: settings.skipRules)
        let language = Self.languageCode(for: sentence.text)
        let expectedVoiceID = "qwen:" + voiceID
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let samples = try await QwenEngine.shared.synthesize(
                    text: spokenText, voiceID: voiceID, language: language, speed: speed
                )
                // `setVoice` resets `nextIndex` to the current sentence,
                // so the index guard alone lets a stale-voice synth
                // poison the cache — match the voice too.
                guard nextIdx == self.nextIndex + 1,
                      SpeechSettings.shared.voiceIdentifier == expectedVoiceID else { return }
                self.prefetchedQwen[nextIdx] = samples
            } catch { /* silent; main path retries */ }
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
        spokenText = ResearchCleanup.clean(spokenText, stripCitations: settings.stripCitations, skipRules: settings.skipRules)
        let expectedVoiceID = "kokoro:" + voiceID
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let samples = try await KokoroEngine.shared.synthesize(
                    text: spokenText, voiceID: voiceID, speed: speed
                )
                // Drop prefetch if the user skipped / stopped / switched
                // voice during synth. A stale voice slipping through
                // here would play the old voice one sentence into the
                // future, after the switch has otherwise landed.
                guard nextIdx == self.nextIndex + 1,
                      SpeechSettings.shared.voiceIdentifier == expectedVoiceID else { return }
                self.prefetchedKokoro[nextIdx] = samples
            } catch {
                // Silent; main-path synth will surface the error.
            }
        }
    }

    // MARK: delegate callbacks (dispatched from main by Delegate)

    fileprivate func didFinishCurrent() {
        // Only advance on real end-of-sentence. A `pcm.stop()` during
        // pause (neural engines) fires the scheduled buffer's
        // completion callback as a side effect — if we advanced here
        // we'd bump `nextIndex` past the sentence the user paused on
        // and fall through to `state = .idle`, so the next Play press
        // would restart from sentence 0 instead of resuming in place.
        guard case .playing = state else { return }
        recordSentenceForStats()
        spokenSubRange = nil
        nextIndex += 1

        // Sleep timer "end of current sentence": the sentence the user
        // was on has finished playing, so pause at the upcoming one
        // rather than continuing. This leaves a `.paused` state with no
        // suspended utterance, matching `seekPaused`/`setVoice`.
        if stopAtNextSentenceBoundary {
            stopAtNextSentenceBoundary = false
            state = nextIndex < sentences.count
                ? .paused(sentenceIndex: nextIndex)
                : .idle
            return
        }

        if nextIndex < sentences.count {
            speakCurrent()
        } else {
            // Genuine end of content. Go idle first, then let the queue
            // (if any) advance — a handler that starts the next item
            // overrides this idle state, so order matters here.
            state = .idle
            onReachedEnd?()
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

    // MARK: language detection

    /// Detects the dominant language of a sentence as an ISO-639
    /// code (e.g. "en", "zh", "ja"). Used by the neural Qwen path
    /// so a bilingual document flips voice character per sentence.
    private static func languageCode(for text: String) -> String {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage?.rawValue ?? "en"
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

    /// Free any neural engine the newly-selected voice no longer needs,
    /// so switching (e.g. Qwen→Kokoro, or →a system voice) doesn't
    /// leave the old model's weights resident for the rest of the
    /// session. Whisper alignment is shared by both neural engines, so
    /// it's released only when switching to a system voice. The unloads
    /// run after the switch so they never delay the new voice starting.
    private static func unloadEngines(notNeededBy identifier: String?) {
        let keep = Engine(for: identifier)
        Task { @MainActor in
            if keep != .kokoro { KokoroEngine.shared.unload() }
            if keep != .qwen { await QwenEngine.shared.unload() }
            if keep == .system { await WhisperAligner.shared.unload() }
        }
    }

    private enum Engine {
        case system
        case kokoro
        case qwen

        /// Which engine a voice identifier routes to, mirroring the
        /// prefix dispatch in `speakCurrent()`.
        init(for voiceID: String?) {
            let id = voiceID ?? ""
            if id.hasPrefix("kokoro:") {
                self = .kokoro
            } else if id.hasPrefix("qwen:") {
                self = .qwen
            } else {
                self = .system
            }
        }
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
