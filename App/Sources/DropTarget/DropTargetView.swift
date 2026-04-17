import SwiftUI

/// The empty-state visual: an SF Symbol, a one-line invitation in
/// New York serif, and a quiet subtitle. Drop handling lives in
/// `RootView` so the drop edge stays armed when a document is open.
struct DropTargetView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(Color.rheaAccent)
            Text("Drop a PDF, Markdown, or EPUB file")
                .font(RheaFont.serif(22))
                .foregroundStyle(.primary)
            Text("We'll read it aloud.")
                .font(RheaFont.ui(13))
                .foregroundStyle(.secondary)
        }
    }
}

#if DEBUG && !RHEA_CLI_BUILD
#Preview {
    DropTargetView()
        .frame(width: 800, height: 600)
        .background(Color.rheaSurface)
}
#endif
