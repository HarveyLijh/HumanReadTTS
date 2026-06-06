import AppKit
import SwiftUI

/// A reading surface: the page background plus the appearance the
/// renderer's dynamic text colors resolve against. The markdown/text
/// renderers paint with system colors (`labelColor`, `secondaryLabelColor`,
/// …), so forcing the text view's `appearance` flips every run to suit the
/// surface without re-rendering, and we only override the background.
enum ReadingTheme: String, CaseIterable, Identifiable, Sendable {
    case system
    case sepia
    case night

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "System"
        case .sepia: return "Sepia"
        case .night: return "Night"
        }
    }

    var subtitle: String {
        switch self {
        case .system: return "Follows light or dark mode"
        case .sepia: return "Warm paper for long reading"
        case .night: return "Dim surface for low light"
        }
    }

    /// Page background, or nil to keep the app's adaptive surface color.
    var background: NSColor? {
        switch self {
        case .system: return nil
        case .sepia: return NSColor(srgbRed: 0.961, green: 0.910, blue: 0.804, alpha: 1)
        case .night: return NSColor(srgbRed: 0.110, green: 0.110, blue: 0.122, alpha: 1)
        }
    }

    /// Forced appearance so dynamic text colors resolve against the
    /// surface; nil follows the system.
    private var appearanceName: NSAppearance.Name? {
        switch self {
        case .system: return nil
        case .sepia: return .aqua
        case .night: return .darkAqua
        }
    }

    var appearance: NSAppearance? {
        appearanceName.flatMap(NSAppearance.init(named:))
    }

    /// SwiftUI color for theming non-text chrome (swatches, containers).
    var swatchColor: Color {
        background.map(Color.init) ?? Color.readAloudTTSSurface
    }

    /// Apply the surface and appearance to a reader's scroll + text view.
    @MainActor
    func apply(toScrollView scroll: NSScrollView, textView: NSTextView) {
        let resolved = appearance
        scroll.appearance = resolved
        textView.appearance = resolved
        let bg = background ?? NSColor(Color.readAloudTTSSurface)
        scroll.backgroundColor = bg
        textView.backgroundColor = bg
    }
}
