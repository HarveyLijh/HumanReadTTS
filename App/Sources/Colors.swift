import SwiftUI

extension Color {
    /// The single warm-amber accent that defines Rhea's visual identity.
    /// Used only for the active highlight, the play button, and focus states.
    static let rheaAccent = Color(red: 0xE8 / 255, green: 0xA0 / 255, blue: 0x33 / 255)

    /// Light-mode paper white. Dark mode resolves to the system near-black.
    static let rheaSurface = Color(
        light: Color(red: 0xFA / 255, green: 0xF9 / 255, blue: 0xF6 / 255),
        dark: Color(red: 0x17 / 255, green: 0x17 / 255, blue: 0x1A / 255)
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
