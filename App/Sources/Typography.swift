import SwiftUI

enum ReadAloudTTSFont {
    /// New York serif at the given point size. Falls back to the system
    /// serif if New York is unavailable on this machine, which never
    /// happens on macOS 15 but the API still requires the fallback.
    static func serif(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    /// SF Pro at the given point size. The system default — explicit
    /// for the rare cases where we want a non-Dynamic-Type size.
    static func ui(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
}
