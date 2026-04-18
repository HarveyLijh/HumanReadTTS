import SwiftUI

extension Color {
    /// The teal accent drawn from the app icon's base fill.
    /// Used only for the active highlight, the play button, and focus states.
    static let rheaAccent = Color(red: 0x5B / 255, green: 0xB8 / 255, blue: 0xC4 / 255)

    /// Reading surface laid over the window's vibrancy backdrop.
    /// Slightly translucent so the macOS behind-window blur shows
    /// through at the edges — matches Notes / Mail / Finder.
    /// Text-level AppKit views (NSScrollView, NSTextView) inherit
    /// this same tint so readability stays consistent.
    static let rheaSurface = Color(
        light: Color(red: 0xFA / 255, green: 0xF9 / 255, blue: 0xF6 / 255)
            .opacity(0.78),
        dark: Color(red: 0x17 / 255, green: 0x17 / 255, blue: 0x1A / 255)
            .opacity(0.72)
    )
}

private extension Color {
    init(light: Color, dark: Color) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            switch appearance.bestMatch(from: [.darkAqua, .aqua]) {
            case .darkAqua: return NSColor(dark)
            default: return NSColor(light)
            }
        })
    }
}
