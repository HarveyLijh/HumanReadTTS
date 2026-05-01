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

    private let defaults: UserDefaults
    private let fontScaleKey = "app.rhea.mac.reader.fontScale.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults.object(forKey: fontScaleKey) != nil {
            let stored = defaults.double(forKey: fontScaleKey)
            fontScale = min(Self.maxScale, max(Self.minScale, stored))
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
    }
}

private extension Double {
    func rounded(toStep step: Double) -> Double {
        (self / step).rounded() * step
    }
}
