import SwiftUI
import UniformTypeIdentifiers

/// The first thing the user sees. Empty state invites them to drop a
/// PDF or Markdown file; once a valid file is dropped, the view shows
/// its path. PDF rendering arrives in M1.2 and replaces the path text.
struct DropTargetView: View {
    @State private var dropped: DroppedDocument?
    @State private var isTargeted = false

    var body: some View {
        ZStack {
            Color.rheaSurface.ignoresSafeArea()

            if let dropped {
                droppedState(dropped)
            } else {
                emptyState
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first, let document = DroppedDocument(url: url) else {
                return false
            }
            dropped = document
            return true
        } isTargeted: { targeted in
            isTargeted = targeted
        }
        .overlay(targetingHighlight)
        .animation(.easeOut(duration: 0.18), value: isTargeted)
        .animation(.easeOut(duration: 0.18), value: dropped)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(Color.rheaAccent)
            Text("Drop a PDF or Markdown file")
                .font(RheaFont.serif(22))
                .foregroundStyle(.primary)
            Text("We'll read it aloud.")
                .font(RheaFont.ui(13))
                .foregroundStyle(.secondary)
        }
    }

    private func droppedState(_ document: DroppedDocument) -> some View {
        VStack(spacing: 12) {
            Image(systemName: document.kind == .pdf ? "doc.richtext" : "doc.plaintext")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Color.rheaAccent)
            Text(document.url.lastPathComponent)
                .font(RheaFont.serif(18))
                .foregroundStyle(.primary)
            Text(document.url.path(percentEncoded: false))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(.horizontal, 24)
                .multilineTextAlignment(.center)
        }
        .padding(32)
    }

    private var targetingHighlight: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(Color.rheaAccent.opacity(isTargeted ? 0.65 : 0), lineWidth: 2)
            .padding(12)
            .allowsHitTesting(false)
    }
}

// `#Preview` relies on a macro plugin that ships with Xcode. The
// `Scripts/build.sh` swiftc fallback for machines without full Xcode
// defines `RHEA_CLI_BUILD` to skip this block.
#if DEBUG && !RHEA_CLI_BUILD
#Preview {
    DropTargetView()
        .frame(width: 800, height: 600)
}
#endif
