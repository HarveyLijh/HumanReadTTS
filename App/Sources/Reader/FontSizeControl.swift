import SwiftUI

/// Compact font-size adjuster used in the header of every non-PDF
/// reader. Backed by `ReaderSettings.shared.fontScale` so all open
/// readers (and the menu shortcuts ⌘+ / ⌘- / ⌘0) stay in lockstep.
@MainActor
struct FontSizeControl: View {
    @Bindable private var settings = ReaderSettings.shared

    var body: some View {
        HStack(spacing: 6) {
            Button {
                settings.decrease()
            } label: {
                Image(systemName: "textformat.size.smaller")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.borderless)
            .help("Decrease font size (\u{2318}-)")

            Slider(
                value: $settings.fontScale,
                in: ReaderSettings.minScale...ReaderSettings.maxScale
            )
            .controlSize(.mini)
            .frame(width: 90)
            .help("Font size: \(percentLabel)")

            Button {
                settings.increase()
            } label: {
                Image(systemName: "textformat.size.larger")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.borderless)
            .help("Increase font size (\u{2318}+)")

            Button {
                settings.reset()
            } label: {
                Text(percentLabel)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 32)
            }
            .buttonStyle(.borderless)
            .help("Reset to 100% (\u{2318}0)")
        }
    }

    private var percentLabel: String {
        "\(Int((settings.fontScale * 100).rounded()))%"
    }
}
