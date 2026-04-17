import SwiftUI

/// Markdown rendering proper lands in M2.7. For M1.x we present the
/// file's raw contents in a monospaced ScrollView so a dropped
/// `.md` file shows *something* useful, and we segment the contents
/// into sentences and feed them to the shared `SpeechPlayer` so
/// playback works the same way it does for PDFs.
///
/// Per-sentence highlighting on this view is not implemented; the
/// proper Markdown reader in M2.7 will support it (the styled
/// AttributedString it builds is the natural place for it). Audio
/// playback alone is enough to unblock the bilingual TTS path on
/// markdown notes today.
struct MarkdownPlaceholderView: View {
    let url: URL
    let player: SpeechPlayer

    @State private var contents: String = ""
    @State private var loadFailed = false

    var body: some View {
        Group {
            if loadFailed {
                errorState
            } else {
                ScrollView {
                    Text(contents)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(24)
                }
            }
        }
        .task(id: url) {
            do {
                let raw = try String(contentsOf: url, encoding: .utf8)
                contents = raw
                loadFailed = false
                let block = DocumentBlock(text: raw, pageIndex: 0, offsetInPage: 0)
                let sentences = await SentenceSegmenter.segment([block])
                player.load(sentences)
            } catch {
                contents = ""
                loadFailed = true
                player.load([])
            }
        }
    }

    private var errorState: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Color.rheaAccent)
            Text("Couldn't read \(url.lastPathComponent).")
                .font(RheaFont.serif(18))
                .foregroundStyle(.primary)
            Text("Drop another file to try again.")
                .font(RheaFont.ui(13))
                .foregroundStyle(.secondary)
        }
        .padding(32)
    }
}
