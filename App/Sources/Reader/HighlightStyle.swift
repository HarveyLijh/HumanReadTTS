import AppKit

/// Single source of truth for the playback highlight colors used by
/// every reader (Markdown, Text, DOCX, EPUB, PDF, Scratchpad). Each of
/// those surfaces used to hard-code
/// `NSColor(Color.readAloudTTSAccent).withAlphaComponent(0.25 / 0.55)`;
/// that recipe now lives here and reads the user's chosen palette and
/// intensity from `ReaderSettings`.
///
/// The active-word band sits a fixed `wordBoost` above the sentence
/// band, so the default (sentence 0.25, word 0.55) reproduces the
/// previous look exactly.
struct HighlightStyle: Equatable {
    /// Background wash under the whole current sentence.
    let sentenceBand: NSColor
    /// Brighter wash under the word being spoken right now.
    let activeWord: NSColor

    /// How much more opaque the active word is than the sentence band.
    static let wordBoost: Double = 0.30
    /// Legible bounds for the sentence-band opacity slider.
    static let minOpacity: Double = 0.15
    static let maxOpacity: Double = 0.70

    /// Pure builder — no `ReaderSettings` dependency, so it is unit
    /// testable. `opacity` is clamped to the same range the settings
    /// slider enforces; the word band is capped so it never goes opaque.
    static func make(palette: HighlightPalette, opacity: Double) -> HighlightStyle {
        let sentenceAlpha = min(maxOpacity, max(minOpacity, opacity))
        let wordAlpha = min(0.9, sentenceAlpha + wordBoost)
        let base = palette.baseColor
        return HighlightStyle(
            sentenceBand: base.withAlphaComponent(sentenceAlpha),
            activeWord: base.withAlphaComponent(wordAlpha)
        )
    }

    /// Live style from the user's current `ReaderSettings`.
    @MainActor
    static var current: HighlightStyle {
        make(
            palette: ReaderSettings.shared.highlightPalette,
            opacity: ReaderSettings.shared.highlightOpacity
        )
    }
}

/// Color-blind-aware highlight palettes. `teal` is the historic default
/// and matches `Color.readAloudTTSAccent`. The others trade hue for
/// luminance separation so the sentence and active-word bands stay
/// distinguishable under common color-vision deficiencies.
enum HighlightPalette: String, CaseIterable, Identifiable, Codable, Sendable {
    case teal
    case blue
    case amber
    case magenta
    case graphite

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .teal: return "Teal"
        case .blue: return "Blue"
        case .amber: return "Amber"
        case .magenta: return "Magenta"
        case .graphite: return "Graphite"
        }
    }

    /// Opaque base color; the alpha is applied by `HighlightStyle.make`.
    /// `teal` reproduces `Color.readAloudTTSAccent` (0x5B/0xB8/0xC4).
    var baseColor: NSColor {
        switch self {
        case .teal:     return NSColor(srgbRed: 0x5B / 255, green: 0xB8 / 255, blue: 0xC4 / 255, alpha: 1)
        case .blue:     return NSColor(srgbRed: 0x3B / 255, green: 0x82 / 255, blue: 0xF6 / 255, alpha: 1)
        case .amber:    return NSColor(srgbRed: 0xF5 / 255, green: 0x9E / 255, blue: 0x0B / 255, alpha: 1)
        case .magenta:  return NSColor(srgbRed: 0xD9 / 255, green: 0x46 / 255, blue: 0xEF / 255, alpha: 1)
        case .graphite: return NSColor(srgbRed: 0x6B / 255, green: 0x72 / 255, blue: 0x80 / 255, alpha: 1)
        }
    }
}
