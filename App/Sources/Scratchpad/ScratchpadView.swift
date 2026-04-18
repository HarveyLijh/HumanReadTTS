import SwiftUI
import AppKit

/// An in-app scratchpad for quick "type and have it read" flows —
/// no need to open a Markdown file first. Lives as a separate
/// document state alongside the PDF / Markdown / EPUB viewers;
/// picking it from File → New drops the user into an editable
/// text area with a Read button that segments the current text
/// into sentences and hands them to the shared SpeechPlayer.
///
/// Segmentation runs at play time (not per keystroke) so typing
/// stays snappy. Highlighting the active sentence in the editor is
/// deferred — the common scratchpad use case is "paste a few
/// paragraphs, listen once" rather than long-form editing; the
/// HUD's scrubber + voice controls still work so the user can seek
/// or switch voices mid-read.
@MainActor
struct ScratchpadView: View {
    let player: SpeechPlayer
    @Binding var text: String

    @State private var isSegmenting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            toolbar
            Divider()
            editor
        }
        .background(Color.rheaSurface)
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 14))
                .foregroundStyle(Color.rheaAccent)
            Text("Scratchpad")
                .font(RheaFont.serif(16))
                .foregroundStyle(.primary)
            Text(characterSummary)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Spacer()

            if isSegmenting {
                ProgressView()
                    .controlSize(.mini)
            }

            Button {
                saveAsMarkdown()
            } label: {
                Label("Save as…", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .help("Export the scratchpad to a .md file.")

            Button {
                readNow()
            } label: {
                Label("Read", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .keyboardShortcut("p", modifiers: [.command])
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .help("Read the scratchpad aloud · ⌘P")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private var editor: some View {
        ScratchpadEditor(text: $text)
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .background(Color.rheaSurface)
    }

    private var characterSummary: String {
        let count = text.count
        if count == 0 { return "Empty — type or paste to begin." }
        if count == 1 { return "1 character" }
        return "\(count) characters"
    }

    /// Segment the current text, load it into the shared player,
    /// and start playback. Segmenting happens on a background task
    /// so very long pastes don't freeze the toolbar.
    private func readNow() {
        let snapshot = text
        guard !snapshot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        isSegmenting = true
        Task { @MainActor in
            let block = DocumentBlock(text: snapshot, pageIndex: 0, offsetInPage: 0)
            let parsed = await SentenceSegmenter.segment([block])
            player.load(parsed)
            isSegmenting = false
            guard !parsed.isEmpty else { return }
            // Small delay before play so the HUD picks up the new
            // sentence count before we start; otherwise the scrubber
            // can flash at 0/0 for a frame.
            try? await Task.sleep(for: .milliseconds(16))
            player.togglePlayPause()
        }
    }

    private func saveAsMarkdown() {
        let panel = NSSavePanel()
        panel.title = "Save Scratchpad"
        panel.allowedContentTypes = [.init(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = "Scratchpad.md"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }
}

/// NSViewRepresentable wrapper around NSTextView — SwiftUI's native
/// `TextEditor` exists on macOS but it's less flexible: no easy way
/// to set a serif font, no pass-through of Markdown typing niceties
/// like smart quotes. Using an NSTextView directly gives us control
/// and matches the editor feel in the rest of the app (PDFs /
/// Markdown viewers all use NSTextView under the hood).
@MainActor
private struct ScratchpadEditor: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.borderType = .noBorder
        scroll.drawsBackground = false

        let textView = NSTextView()
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.delegate = context.coordinator
        textView.font = NSFont(name: "New York", size: 16) ?? NSFont.systemFont(ofSize: 16)
        textView.textColor = NSColor.labelColor
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: 0, height: CGFloat.greatestFiniteMagnitude
        )
        textView.string = text

        let para = NSMutableParagraphStyle()
        para.lineHeightMultiple = 1.35
        textView.defaultParagraphStyle = para
        textView.typingAttributes = [
            .font: textView.font ?? NSFont.systemFont(ofSize: 16),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: para,
        ]

        scroll.documentView = textView
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        // Only overwrite if the host's text diverged from the view —
        // avoids blowing away the user's in-flight typing because
        // SwiftUI re-rendered the parent.
        if textView.string != text {
            textView.string = text
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let text: Binding<String>
        init(text: Binding<String>) { self.text = text }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }
    }
}
