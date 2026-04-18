import AppKit

/// NSTextView subclass the Markdown + EPUB readers host.
/// Adds two affordances that Speechify-grade readers have:
///
/// - **Double-click to start reading from here.** The native
///   NSTextView interpretation of double-click is "select the
///   clicked word", which we keep — but we also capture the
///   same character index and notify the host so playback seeks
///   to the sentence containing that word.
/// - **Right-click → Read from here.** Appended to the default
///   contextual menu (copy, look up, etc.) so the user doesn't
///   lose the system-provided actions.
///
/// Offsets are reported as UTF-16 indices against the view's
/// `string`, matching what `SentenceSegmenter` and `Sentence`
/// use. The host resolves the offset to a sentence index via
/// `ReaderHitTester` before calling into `SpeechPlayer`.
final class ClickableReaderTextView: NSTextView {
    /// Called with the UTF-16 offset under the mouse on
    /// double-click or the "Read from here" menu item. The host
    /// is responsible for mapping the offset to a sentence and
    /// triggering playback.
    var onReadFromOffset: ((Int) -> Void)?

    /// Offset captured at the last right-click, used by the
    /// menu validation + action so the selector sees the same
    /// click point the menu opened at.
    private var pendingMenuOffset: Int?

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        guard event.clickCount == 2 else { return }
        let offset = characterOffset(for: event)
        guard offset >= 0 else { return }
        onReadFromOffset?(offset)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        let offset = characterOffset(for: event)
        guard offset >= 0 else { return menu }
        pendingMenuOffset = offset

        let item = NSMenuItem(
            title: "Read from here",
            action: #selector(readFromHere(_:)),
            keyEquivalent: ""
        )
        item.target = self
        if menu.items.isEmpty {
            menu.addItem(item)
        } else {
            menu.insertItem(.separator(), at: 0)
            menu.insertItem(item, at: 0)
        }
        return menu
    }

    @objc private func readFromHere(_ sender: Any?) {
        guard let offset = pendingMenuOffset else { return }
        pendingMenuOffset = nil
        onReadFromOffset?(offset)
    }

    /// Translates a window-space `NSEvent` to the UTF-16 offset
    /// of the character under the pointer. NSTextView's
    /// `characterIndexForInsertion(at:)` speaks view coordinates,
    /// so we convert window → view first.
    private func characterOffset(for event: NSEvent) -> Int {
        let point = convert(event.locationInWindow, from: nil)
        return characterIndexForInsertion(at: point)
    }
}
