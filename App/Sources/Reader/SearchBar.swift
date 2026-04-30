import SwiftUI
import AppKit

/// Search options shared by the markdown and PDF readers. Held as a
/// `@Bindable` model class so the SwiftUI search bar binds two-way to
/// the same instance the host view uses to drive its match engine.
@Observable
@MainActor
final class SearchState {
    var isPresented: Bool = false
    var query: String = ""
    var useRegex: Bool = false
    var caseSensitive: Bool = false
    /// Number of matches the host view found for the current query.
    /// The host updates this after running a search.
    var totalMatches: Int = 0
    /// Index of the currently-active match, 0-based. -1 when none.
    var currentIndex: Int = -1

    func reset() {
        query = ""
        totalMatches = 0
        currentIndex = -1
    }
}

/// Find / regex / case bar that lives in the top-right of a reader.
/// Hosts wire `onSubmit` (run search), `onNext` / `onPrev` (cycle
/// matches), and `onDismiss` (Esc). The bar itself is purely a view
/// — actual matching against text storage / PDF content lives in the
/// host because the data structures differ.
struct SearchBar: View {
    @Bindable var state: SearchState
    var onSubmit: () -> Void
    var onNext: () -> Void
    var onPrev: () -> Void
    var onDismiss: () -> Void

    @FocusState private var fieldFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            TextField("Find", text: $state.query)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .frame(minWidth: 140, idealWidth: 180, maxWidth: 220)
                .focused($fieldFocused)
                .onSubmit { onNext() }
                .onChange(of: state.query) { _, _ in onSubmit() }
                .onChange(of: state.useRegex) { _, _ in onSubmit() }
                .onChange(of: state.caseSensitive) { _, _ in onSubmit() }

            Toggle(isOn: $state.caseSensitive) {
                Text("Aa")
                    .font(.system(size: 11, weight: .semibold))
            }
            .toggleStyle(.button)
            .controlSize(.mini)
            .help("Match case")

            Toggle(isOn: $state.useRegex) {
                Text(".*")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
            }
            .toggleStyle(.button)
            .controlSize(.mini)
            .help("Regular expression")

            Text(matchLabel)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(minWidth: 56, alignment: .trailing)

            Button(action: onPrev) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .disabled(state.totalMatches == 0)
            .keyboardShortcut("g", modifiers: [.command, .shift])
            .help("Previous match (\u{21E7}\u{2318}G)")

            Button(action: onNext) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .disabled(state.totalMatches == 0)
            .keyboardShortcut("g", modifiers: [.command])
            .help("Next match (\u{2318}G)")

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(.escape, modifiers: [])
            .help("Close (Esc)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        .onAppear { fieldFocused = true }
        .onChange(of: state.isPresented) { _, presented in
            if presented { fieldFocused = true }
        }
    }

    private var matchLabel: String {
        if state.query.isEmpty { return "" }
        if state.totalMatches == 0 { return "No results" }
        return "\(state.currentIndex + 1) of \(state.totalMatches)"
    }
}

/// Plain-text / regex matcher used by the markdown reader. Returns
/// every match as an `NSRange` against the input string so the caller
/// can paint highlights on its `NSTextStorage`.
enum TextSearcher {
    @MainActor
    static func search(in text: String, options: SearchState) -> [NSRange] {
        let query = options.query
        guard !query.isEmpty, !text.isEmpty else { return [] }

        if options.useRegex {
            var regexOptions: NSRegularExpression.Options = []
            if !options.caseSensitive {
                regexOptions.insert(.caseInsensitive)
            }
            guard let regex = try? NSRegularExpression(
                pattern: query, options: regexOptions
            ) else {
                return []
            }
            let nsText = text as NSString
            let full = NSRange(location: 0, length: nsText.length)
            return regex.matches(in: text, options: [], range: full)
                .map(\.range)
                .filter { $0.length > 0 }
        }

        let nsText = text as NSString
        var matches: [NSRange] = []
        var cursor = 0
        let opts: NSString.CompareOptions = options.caseSensitive
            ? []
            : [.caseInsensitive]
        while cursor < nsText.length {
            let scan = NSRange(location: cursor, length: nsText.length - cursor)
            let found = nsText.range(of: query, options: opts, range: scan)
            if found.location == NSNotFound { break }
            matches.append(found)
            cursor = found.location + max(found.length, 1)
        }
        return matches
    }
}
