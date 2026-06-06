import AppKit
import Foundation

/// "Leading bold" (a.k.a. bionic) reading: bolds the first few characters
/// of each word so the eye anchors on word beginnings. Opt-in and off by
/// default. Applied as a post-pass on an already-rendered attributed
/// string, it only adds the bold font trait to leading glyphs — it never
/// changes characters, so a reader's cached sentence offsets and playback
/// alignment stay valid.
enum BionicReading {
    /// How many leading characters to bold for a word of `wordLength`.
    /// Short words bold a single character; longer words bold ~40%,
    /// capped so a long word never turns mostly bold.
    static func boldPrefixLength(wordLength: Int) -> Int {
        switch wordLength {
        case ..<1: return 0
        case 1...3: return 1
        case 4...6: return 2
        default: return min(Int((Double(wordLength) * 0.4).rounded()), 5)
        }
    }

    /// Bolds the leading fraction of every word in `storage`, in place.
    /// Uses `NSFontManager` so the bold trait composes with whatever face
    /// the reader picked (including the bundled accessibility fonts).
    static func emphasize(_ storage: NSMutableAttributedString) {
        guard storage.length > 0 else { return }
        let text = storage.string as NSString
        let full = NSRange(location: 0, length: text.length)
        let manager = NSFontManager.shared
        text.enumerateSubstrings(in: full, options: [.byWords, .localized]) { _, wordRange, _, _ in
            let n = boldPrefixLength(wordLength: wordRange.length)
            guard n > 0 else { return }
            let boldRange = NSRange(location: wordRange.location, length: min(n, wordRange.length))
            storage.enumerateAttribute(.font, in: boldRange, options: []) { value, subRange, _ in
                let base = (value as? NSFont) ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
                let bold = manager.convert(base, toHaveTrait: .boldFontMask)
                storage.addAttribute(.font, value: bold, range: subRange)
            }
        }
    }
}
