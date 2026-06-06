import AppKit
import SwiftUI

/// Presents the tap-to-translate popover anchored on the tapped word.
/// Shared by every reader because they all host `ClickableReaderTextView`;
/// the text view hands us a character offset and itself, and we resolve
/// the word, its sentence context, and its on-screen rect from there.
@MainActor
final class TranslationPopoverController {
    static let shared = TranslationPopoverController()

    private var popover: NSPopover?

    /// Show the popover for the word covering `offset` in `textView`.
    /// No-op when tap-to-translate is off or the offset isn't on a word
    /// (whitespace/punctuation), so a stray Option-double-click is quiet.
    func present(forWordAt offset: Int, in textView: NSTextView) {
        guard LearningSettings.shared.tapToTranslateEnabled else { return }
        let text = textView.string
        guard let range = WordRangeResolver.wordRange(in: text, at: offset),
              let word = WordRangeResolver.word(in: text, at: offset) else { return }

        let context = WordRangeResolver.sentence(in: text, at: offset) ?? ""
        let detected = SentenceSegmenter.detectLanguage(context.isEmpty ? word : context)
        let anchor = boundingRect(of: range, in: textView)

        popover?.close()
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        let controller = self
        popover.contentViewController = NSHostingController(
            rootView: TranslationPopoverView(
                word: word,
                context: context,
                sourceLanguage: detected,
                onDismiss: { [weak controller] in controller?.popover?.performClose(nil) }
            )
        )
        popover.show(relativeTo: anchor, of: textView, preferredEdge: .maxY)
        self.popover = popover
    }

    /// Bounding rect of `range` in the text view's coordinate space, used
    /// to anchor the popover under the word. Falls back to a 1pt rect at
    /// the origin if the layout manager can't be reached.
    private func boundingRect(of range: NSRange, in textView: NSTextView) -> NSRect {
        guard let layoutManager = textView.layoutManager,
              let container = textView.textContainer else {
            return NSRect(x: 0, y: 0, width: 1, height: 1)
        }
        let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: container)
        let origin = textView.textContainerOrigin
        rect.origin.x += origin.x
        rect.origin.y += origin.y
        return rect
    }
}
