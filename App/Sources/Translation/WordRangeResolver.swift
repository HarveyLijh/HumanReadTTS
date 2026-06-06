import Foundation
import NaturalLanguage

/// Resolves the word under a character offset so the translation popover
/// can look up exactly what the user pointed at. Uses `NLTokenizer`'s
/// word unit, which segments space-delimited scripts and space-less ones
/// (Chinese, Japanese) alike — clicking a Chinese character yields its
/// whole word (一/两/三 characters), not a lone glyph.
///
/// Offsets are UTF-16 (NSString units), matching `Sentence` and the
/// reader text views.
enum WordRangeResolver {
    /// The UTF-16 range of the word covering `utf16Index`, or nil when
    /// the index lands on whitespace or punctuation between words.
    static func wordRange(in text: String, at utf16Index: Int) -> NSRange? {
        let ns = text as NSString
        guard utf16Index >= 0, utf16Index < ns.length else { return nil }
        let stringIndex = String.Index(utf16Offset: utf16Index, in: text)
        guard stringIndex < text.endIndex else { return nil }

        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        let tokenRange = tokenizer.tokenRange(at: stringIndex)
        guard !tokenRange.isEmpty else { return nil }

        let nsRange = NSRange(tokenRange, in: text)
        // tokenRange(at:) can snap to a neighbor; require the index to
        // actually fall inside the returned token.
        guard nsRange.location <= utf16Index, utf16Index < NSMaxRange(nsRange) else { return nil }

        // Skip pure-punctuation tokens so clicking a comma resolves to
        // nothing rather than translating "," .
        let word = ns.substring(with: nsRange)
        guard word.rangeOfCharacter(from: .alphanumerics) != nil else { return nil }
        return nsRange
    }

    /// The word substring covering `utf16Index`, or nil.
    static func word(in text: String, at utf16Index: Int) -> String? {
        guard let range = wordRange(in: text, at: utf16Index) else { return nil }
        return (text as NSString).substring(with: range)
    }
}
