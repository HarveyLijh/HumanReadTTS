import Foundation
import Observation

/// Per-document font size preference for the non-PDF readers
/// (Markdown, EPUB, Scratchpad). PDFs use PDFKit's native zoom and
/// are unaffected. Persisted as a multiplier so it composes with
/// each reader's own base sizes (markdown body=16pt, scratchpad
/// editor=16pt, EPUB-supplied per-run sizes).
@Observable
@MainActor
final class ReaderSettings {
    static let shared = ReaderSettings()

    /// 1.0 = unchanged. Clamped to [minScale, maxScale] on every set
    /// so the keyboard shortcuts and slider can't drive the body
    /// text into an unreadable extreme.
    var fontScale: Double = 1.0 {
        didSet {
            let clamped = min(Self.maxScale, max(Self.minScale, fontScale))
            if clamped != fontScale {
                fontScale = clamped
                return
            }
            defaults.set(fontScale, forKey: fontScaleKey)
        }
    }

    static let minScale: Double = 0.6
    static let maxScale: Double = 2.5
    /// Step used by ⌘+ / ⌘-. Matches the slider's perceived "click".
    static let step: Double = 0.1

    /// Playback-highlight palette (color-blind-aware). Default `.teal`
    /// reproduces the historic accent highlight; read by
    /// `HighlightStyle.current`.
    var highlightPalette: HighlightPalette = .teal {
        didSet { defaults.set(highlightPalette.rawValue, forKey: highlightPaletteKey) }
    }

    /// Opacity of the sentence highlight band. The active-word band is
    /// derived from this (`+ HighlightStyle.wordBoost`). Clamped to a
    /// legible range on every set, like `fontScale`.
    var highlightOpacity: Double = 0.25 {
        didSet {
            let clamped = min(HighlightStyle.maxOpacity, max(HighlightStyle.minOpacity, highlightOpacity))
            if clamped != highlightOpacity {
                highlightOpacity = clamped
                return
            }
            defaults.set(highlightOpacity, forKey: highlightOpacityKey)
        }
    }

    /// Body typeface for the synthesized readers (Markdown, plain text,
    /// Scratchpad preview). `.serif` reproduces the historic New York
    /// look, so the default leaves existing documents unchanged.
    var fontFace: ReaderFontFace = .serif {
        didSet { defaults.set(fontFace.rawValue, forKey: fontFaceKey) }
    }

    /// Line-height multiple. Clamped to a readable band like `fontScale`.
    var lineSpacingMultiple: Double = 1.25 {
        didSet {
            let clamped = min(2.2, max(1.0, lineSpacingMultiple))
            if clamped != lineSpacingMultiple {
                lineSpacingMultiple = clamped
                return
            }
            defaults.set(lineSpacingMultiple, forKey: lineSpacingMultipleKey)
        }
    }

    /// Extra inter-glyph spacing in points (0 = the font's own metrics).
    var letterSpacing: Double = 0 {
        didSet {
            let clamped = min(2.5, max(0, letterSpacing))
            if clamped != letterSpacing {
                letterSpacing = clamped
                return
            }
            defaults.set(letterSpacing, forKey: letterSpacingKey)
        }
    }

    /// "Bionic"/leading-bold reading: bold the start of each word.
    var leadingBoldEnabled: Bool = false {
        didSet { defaults.set(leadingBoldEnabled, forKey: leadingBoldKey) }
    }

    /// Reading surface (page background + appearance). `.system` keeps the
    /// historic adaptive surface, so existing readers look unchanged.
    var readingTheme: ReadingTheme = .system {
        didSet { defaults.set(readingTheme.rawValue, forKey: readingThemeKey) }
    }

    private let defaults: UserDefaults
    private let fontScaleKey = "app.readaloudtts.mac.reader.fontScale.v1"
    private let highlightPaletteKey = "app.readaloudtts.mac.reader.highlightPalette.v1"
    private let highlightOpacityKey = "app.readaloudtts.mac.reader.highlightOpacity.v1"
    private let fontFaceKey = "app.readaloudtts.mac.reader.fontFace.v1"
    private let lineSpacingMultipleKey = "app.readaloudtts.mac.reader.lineSpacingMultiple.v1"
    private let letterSpacingKey = "app.readaloudtts.mac.reader.letterSpacing.v1"
    private let leadingBoldKey = "app.readaloudtts.mac.reader.leadingBold.v1"
    private let readingThemeKey = "app.readaloudtts.mac.reader.readingTheme.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults.object(forKey: fontScaleKey) != nil {
            let stored = defaults.double(forKey: fontScaleKey)
            fontScale = min(Self.maxScale, max(Self.minScale, stored))
        }
        if let raw = defaults.string(forKey: highlightPaletteKey),
           let palette = HighlightPalette(rawValue: raw) {
            highlightPalette = palette
        }
        if defaults.object(forKey: highlightOpacityKey) != nil {
            let stored = defaults.double(forKey: highlightOpacityKey)
            highlightOpacity = min(HighlightStyle.maxOpacity, max(HighlightStyle.minOpacity, stored))
        }
        if let raw = defaults.string(forKey: fontFaceKey),
           let face = ReaderFontFace(rawValue: raw) {
            fontFace = face
        }
        if defaults.object(forKey: lineSpacingMultipleKey) != nil {
            let stored = defaults.double(forKey: lineSpacingMultipleKey)
            lineSpacingMultiple = min(2.2, max(1.0, stored))
        }
        if defaults.object(forKey: letterSpacingKey) != nil {
            let stored = defaults.double(forKey: letterSpacingKey)
            letterSpacing = min(2.5, max(0, stored))
        }
        if defaults.object(forKey: leadingBoldKey) != nil {
            leadingBoldEnabled = defaults.bool(forKey: leadingBoldKey)
        }
        if let raw = defaults.string(forKey: readingThemeKey),
           let theme = ReadingTheme(rawValue: raw) {
            readingTheme = theme
        }
    }

    func increase() {
        fontScale = (fontScale + Self.step).rounded(toStep: Self.step)
    }

    func decrease() {
        fontScale = (fontScale - Self.step).rounded(toStep: Self.step)
    }

    func reset() {
        fontScale = 1.0
        highlightPalette = .teal
        highlightOpacity = 0.25
        fontFace = .serif
        lineSpacingMultiple = 1.25
        letterSpacing = 0
        leadingBoldEnabled = false
        readingTheme = .system
    }
}

private extension Double {
    func rounded(toStep step: Double) -> Double {
        (self / step).rounded() * step
    }
}
