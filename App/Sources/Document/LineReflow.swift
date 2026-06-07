import Foundation

/// Reflows text that arrives segregated by *visual* lines (PDFs, OCR
/// output, text exported from a PDF) back into flowing paragraphs.
///
/// Layout-wrapped sources put a hard line break at the end of every
/// rendered line, not every sentence. `NLTokenizer(unit: .sentence)`
/// treats such a break as a sentence boundary, so each wrapped line
/// becomes its own "sentence" and the reader highlights/reads one line
/// at a time. Replacing wrap breaks with spaces lets the tokenizer see
/// the real sentence that spans those lines.
///
/// The transform is **length-preserving**: every line-break character
/// is overwritten in place with a space, so the UTF-16 length and every
/// offset are identical to the input. That is what lets the highlight
/// layer keep mapping a sentence to its on-page `PDFSelection` (or to a
/// range in the displayed text) using offsets computed from the
/// reflowed copy without any remapping.
enum LineReflow {
    /// Replaces a *single* line break (a wrap within a paragraph) with a
    /// space, while leaving a run of two-or-more line breaks (a
    /// paragraph separator / blank line) intact. A `\r\n` pair counts as
    /// one logical break. Length-preserving; handles `\n`, `\r`, `\r\n`.
    static func reflow(_ text: String) -> String {
        let ns = text as NSString
        let length = ns.length
        guard length > 0 else { return text }

        var chars = [unichar](repeating: 0, count: length)
        ns.getCharacters(&chars)

        var i = 0
        while i < length {
            guard isLineBreak(chars[i]) else {
                i += 1
                continue
            }
            // Measure the run of consecutive logical line breaks starting
            // at i, where a `\r\n` pair counts as a single break.
            var breakCount = 0
            var j = i
            while j < length, isLineBreak(chars[j]) {
                if chars[j] == 0x0D, j + 1 < length, chars[j + 1] == 0x0A {
                    j += 2
                } else {
                    j += 1
                }
                breakCount += 1
            }
            // A single break is a wrap: overwrite its character(s) with
            // spaces in place (length-preserving). Two or more breaks are
            // a paragraph separator and are left untouched.
            if breakCount == 1 {
                for k in i..<j { chars[k] = 0x20 }
            }
            i = j
        }

        return String(utf16CodeUnits: chars, count: length)
    }

    private static func isLineBreak(_ ch: unichar) -> Bool {
        ch == 0x0A || ch == 0x0D
    }
}
