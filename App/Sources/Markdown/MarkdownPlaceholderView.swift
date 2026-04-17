import SwiftUI

/// Markdown rendering proper lands in M2.7. For M1.2 we just present
/// the file's raw contents in a monospaced ScrollView so a dropped
/// `.md` file shows *something* useful rather than a placeholder.
struct MarkdownPlaceholderView: View {
    let url: URL

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
                contents = try String(contentsOf: url, encoding: .utf8)
                loadFailed = false
            } catch {
                contents = ""
                loadFailed = true
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
