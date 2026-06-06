import AppKit
import Foundation

/// The reader body typeface. `.serif` (New York) reproduces the historic
/// reader font and is therefore the default, so enabling typography
/// controls never changes how an existing document looks until the user
/// picks a different face. `.openDyslexic` and `.atkinsonHyperlegible`
/// are SIL-OFL faces bundled in the app and registered at launch by
/// `ReaderFonts.registerBundledFonts()`.
enum ReaderFontFace: String, CaseIterable, Identifiable, Sendable {
    case serif
    case system
    case sansSerif
    case monospaced
    case openDyslexic
    case atkinsonHyperlegible

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .serif: return "Serif — New York"
        case .system: return "System"
        case .sansSerif: return "Sans Serif — Helvetica Neue"
        case .monospaced: return "Monospaced"
        case .openDyslexic: return "OpenDyslexic"
        case .atkinsonHyperlegible: return "Atkinson Hyperlegible"
        }
    }

    /// A one-line note shown beside the picker so users understand the
    /// two accessibility faces.
    var subtitle: String? {
        switch self {
        case .openDyslexic:
            return "Weighted letter bottoms to reduce flipping (dyslexia)."
        case .atkinsonHyperlegible:
            return "High character distinction for low vision."
        default:
            return nil
        }
    }

    /// True for the two faces shipped inside the app bundle (their
    /// licenses are attributed in the Reading settings tab).
    var isBundled: Bool { self == .openDyslexic || self == .atkinsonHyperlegible }

    /// The regular cut at `size`. Bold/italic are derived by callers
    /// through `NSFontManager`, which resolves the matching member of
    /// the same family (e.g. `OpenDyslexic-Bold`) once the bundled fonts
    /// are registered. Every branch falls back to the system font so a
    /// missing or unregistered face degrades instead of returning nil.
    func baseFont(size: CGFloat) -> NSFont {
        switch self {
        case .serif:
            return NSFont(name: "New York", size: size) ?? .systemFont(ofSize: size)
        case .system:
            return .systemFont(ofSize: size)
        case .sansSerif:
            return NSFont(name: "Helvetica Neue", size: size) ?? .systemFont(ofSize: size)
        case .monospaced:
            return .monospacedSystemFont(ofSize: size, weight: .regular)
        case .openDyslexic:
            return NSFont(name: "OpenDyslexic", size: size)
                ?? NSFont(name: "OpenDyslexic-Regular", size: size)
                ?? .systemFont(ofSize: size)
        case .atkinsonHyperlegible:
            return NSFont(name: "Atkinson Hyperlegible", size: size)
                ?? NSFont(name: "AtkinsonHyperlegible-Regular", size: size)
                ?? .systemFont(ofSize: size)
        }
    }
}

/// An immutable snapshot of the reader's comfort-typography choices,
/// derived from `ReaderSettings`. Readers build their `NSFont`s and
/// paragraph styles from this so the body face, line height, and letter
/// spacing stay consistent across Markdown, plain text, and the
/// Scratchpad preview. It is `Equatable` so an `NSViewRepresentable` can
/// skip a restyle when nothing changed.
struct ReaderTypography: Equatable, Sendable {
    var face: ReaderFontFace
    /// Line-height multiple applied to the paragraph style. 1.25 is the
    /// historic default.
    var lineHeightMultiple: CGFloat
    /// Extra inter-glyph spacing in points. 0 = the font's native metrics.
    var letterSpacing: CGFloat
    /// When true, the leading characters of each word are bolded
    /// ("bionic"/leading-bold reading). Off reproduces the plain look.
    var leadingBold: Bool

    init(
        face: ReaderFontFace = .serif,
        lineHeightMultiple: CGFloat = 1.25,
        letterSpacing: CGFloat = 0,
        leadingBold: Bool = false
    ) {
        self.face = face
        self.lineHeightMultiple = lineHeightMultiple
        self.letterSpacing = letterSpacing
        self.leadingBold = leadingBold
    }

    @MainActor
    init(from settings: ReaderSettings) {
        self.init(
            face: settings.fontFace,
            lineHeightMultiple: CGFloat(settings.lineSpacingMultiple),
            letterSpacing: CGFloat(settings.letterSpacing),
            leadingBold: settings.leadingBoldEnabled
        )
    }

    /// The regular body font at `size`.
    func baseFont(size: CGFloat) -> NSFont { face.baseFont(size: size) }

    /// `.kern` value, or nil when letter spacing is off so the default
    /// reading path emits no kern attribute and is byte-for-byte the
    /// same attributed string as before this feature.
    var kern: CGFloat? { letterSpacing == 0 ? nil : letterSpacing }

    /// A fresh paragraph style carrying the user's line height. Callers
    /// set `paragraphSpacing` themselves since it is reader-specific.
    func paragraphStyle(paragraphSpacing: CGFloat = 0) -> NSMutableParagraphStyle {
        let para = NSMutableParagraphStyle()
        para.lineHeightMultiple = lineHeightMultiple
        para.paragraphSpacing = paragraphSpacing
        return para
    }
}

/// Registers the bundled SIL-OFL fonts with Core Text once per process
/// so `NSFont(name:)` resolves them. Bundling and registering at runtime
/// (instead of via `ATSApplicationFontsPath`) keeps the hand-maintained
/// project free of a folder reference and works regardless of where the
/// resources land in the built bundle.
enum ReaderFonts {
    /// PostScript / file base names of the bundled `.otf` resources.
    static let bundledFontResourceNames = [
        "OpenDyslexic-Regular",
        "OpenDyslexic-Bold",
        "AtkinsonHyperlegible-Regular",
        "AtkinsonHyperlegible-Bold",
    ]

    @MainActor private static var didRegister = false

    @MainActor
    static func registerBundledFonts(in bundle: Bundle = .main) {
        guard !didRegister else { return }
        didRegister = true
        let urls = bundledFontResourceNames.compactMap {
            bundle.url(forResource: $0, withExtension: "otf")
        }
        guard !urls.isEmpty else { return }
        CTFontManagerRegisterFontURLs(urls as CFArray, .process, true, nil)
    }
}
