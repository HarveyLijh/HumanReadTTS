import SwiftUI
import AppKit

/// Reading-comfort settings: body typeface, spacing, and the playback
/// highlight. Everything here binds to `ReaderSettings.shared`, so the
/// open readers (Markdown, plain text, Scratchpad) restyle live as the
/// user drags a slider or picks a face. Live previews sit beside the
/// controls so the effect is visible without leaving the window.
struct ReadingSettingsView: View {
    @Bindable private var reader = ReaderSettings.shared

    private let sampleText =
        "The quick brown fox jumps over the lazy dog while the reader follows along."

    var body: some View {
        Form {
            bodyTextSection
            themeSection
            highlightSection
            attributionSection

            Section {
                Button("Reset to defaults", role: .destructive) {
                    reader.reset()
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Body text

    private var bodyTextSection: some View {
        Section {
            Picker("Font", selection: $reader.fontFace) {
                ForEach(ReaderFontFace.allCases) { face in
                    Text(face.displayName).tag(face)
                }
            }
            if let subtitle = reader.fontFace.subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            slider("Size", value: $reader.fontScale,
                   range: ReaderSettings.minScale...ReaderSettings.maxScale,
                   step: 0.05, format: "%.0f%%", scale: 100)

            slider("Line spacing", value: $reader.lineSpacingMultiple,
                   range: 1.0...2.2, step: 0.05, format: "%.2f×")

            slider("Letter spacing", value: $reader.letterSpacing,
                   range: 0...2.5, step: 0.1, format: "%.1f pt")

            Toggle("Leading-bold (bionic) reading", isOn: $reader.leadingBoldEnabled)
                .help("Bolds the start of each word so the eye anchors on word beginnings.")

            samplePreview
        } header: {
            Text("Body Text")
        } footer: {
            Text("Applies to Markdown, plain-text, and Scratchpad reading. EPUB and DOCX keep their own fonts and follow the size only.")
                .foregroundStyle(.secondary)
        }
    }

    private var samplePreview: some View {
        Text(sampleText)
            .font(Font(reader.fontFace.baseFont(size: 17 * reader.fontScale) as CTFont))
            .lineSpacing((reader.lineSpacingMultiple - 1.0) * 17 * reader.fontScale)
            .kerning(reader.letterSpacing)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.readAloudTTSSurface, in: RoundedRectangle(cornerRadius: 8))
            .accessibilityLabel("Live preview of the selected reading font and spacing")
    }

    // MARK: - Reading theme

    private var themeSection: some View {
        Section {
            Picker("Surface", selection: $reader.readingTheme) {
                ForEach(ReadingTheme.allCases) { theme in
                    HStack {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(theme.swatchColor)
                            .frame(width: 16, height: 12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 3)
                                    .strokeBorder(Color.secondary.opacity(0.3))
                            )
                        Text(theme.displayName)
                    }
                    .tag(theme)
                }
            }
            Text(reader.readingTheme.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)

            themePreview
        } header: {
            Text("Reading Theme")
        } footer: {
            Text("Tints the page behind Markdown, plain-text, and Scratchpad reading. Sepia and Night set their own light/dark text so the page stays comfortable regardless of system appearance.")
                .foregroundStyle(.secondary)
        }
    }

    private var themePreview: some View {
        let theme = reader.readingTheme
        return Text(sampleText)
            .font(Font(reader.fontFace.baseFont(size: 15 * reader.fontScale) as CTFont))
            .foregroundStyle(theme == .night ? Color.white.opacity(0.92) : Color.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(theme.swatchColor, in: RoundedRectangle(cornerRadius: 8))
            .environment(\.colorScheme, theme == .night ? .dark : .light)
            .accessibilityLabel("Live preview of the \(theme.displayName) reading surface")
    }

    // MARK: - Highlight

    private var highlightSection: some View {
        Section {
            Picker("Color", selection: $reader.highlightPalette) {
                ForEach(HighlightPalette.allCases) { palette in
                    HStack {
                        Circle()
                            .fill(Color(nsColor: palette.baseColor))
                            .frame(width: 11, height: 11)
                        Text(palette.displayName)
                    }
                    .tag(palette)
                }
            }

            slider("Intensity", value: $reader.highlightOpacity,
                   range: HighlightStyle.minOpacity...HighlightStyle.maxOpacity,
                   step: 0.05, format: "%.0f%%", scale: 100)

            highlightPreview
        } header: {
            Text("Playback Highlight")
        } footer: {
            Text("The brighter band marks the word being spoken; the softer band marks the sentence. Alternatives trade hue for lightness so the two stay distinct under color-vision deficiencies.")
                .foregroundStyle(.secondary)
        }
    }

    private var highlightPreview: some View {
        let style = HighlightStyle.make(
            palette: reader.highlightPalette,
            opacity: reader.highlightOpacity
        )
        var attributed = AttributedString(
            "The reader highlights the current sentence as it speaks."
        )
        attributed.backgroundColor = Color(nsColor: style.sentenceBand)
        if let word = attributed.range(of: "highlights") {
            attributed[word].backgroundColor = Color(nsColor: style.activeWord)
        }
        return Text(attributed)
            .font(.system(size: 14))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.readAloudTTSSurface, in: RoundedRectangle(cornerRadius: 8))
            .accessibilityLabel("Live preview of the playback highlight colors")
    }

    // MARK: - Attribution

    private var attributionSection: some View {
        Section {
            Text("OpenDyslexic and Atkinson Hyperlegible are bundled under the SIL Open Font License 1.1.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("Fonts")
        }
    }

    // MARK: - Helpers

    /// A labeled slider with a right-aligned monospaced readout. `scale`
    /// multiplies the value before formatting (e.g. 100 to show a
    /// fraction as a percentage).
    private func slider(
        _ label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        format: String,
        scale: Double = 1
    ) -> some View {
        LabeledContent {
            HStack(spacing: 12) {
                Slider(value: value, in: range, step: step)
                Text(String(format: format, value.wrappedValue * scale))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 56, alignment: .trailing)
            }
        } label: {
            Text(label)
        }
    }
}
