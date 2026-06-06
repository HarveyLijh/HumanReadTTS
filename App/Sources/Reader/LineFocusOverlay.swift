import SwiftUI

/// A reading ruler: when enabled, dims the page except for a horizontal
/// band that follows the pointer, so the eye stays on one line. Helps
/// readers who lose their place or are distracted by surrounding text.
///
/// The dimming overlay never takes hit-testing, so clicking to read,
/// selecting, and scrolling all work normally underneath it. The band
/// fades away when the pointer leaves the reading area.
private struct LineFocusModifier: ViewModifier {
    let enabled: Bool
    let bandHeight: CGFloat

    @State private var pointerY: CGFloat?

    private let dimOpacity = 0.45

    func body(content: Content) -> some View {
        content
            .onContinuousHover { phase in
                guard enabled else { pointerY = nil; return }
                switch phase {
                case .active(let point): pointerY = point.y
                case .ended: pointerY = nil
                }
            }
            .overlay {
                if enabled, let y = pointerY {
                    GeometryReader { geo in
                        let height = geo.size.height
                        let top = max(0, min(height, y - bandHeight / 2))
                        let bottom = max(top, min(height, y + bandHeight / 2))
                        VStack(spacing: 0) {
                            Color.black.opacity(dimOpacity)
                                .frame(height: top)
                            Color.clear
                                .frame(height: bottom - top)
                            Color.black.opacity(dimOpacity)
                                .frame(height: height - bottom)
                        }
                    }
                    .allowsHitTesting(false)
                    .animation(.easeOut(duration: 0.07), value: y)
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.15), value: enabled)
    }
}

extension View {
    /// Dim the page outside a pointer-following band. No-op when disabled.
    func lineFocus(enabled: Bool, bandHeight: CGFloat) -> some View {
        modifier(LineFocusModifier(enabled: enabled, bandHeight: bandHeight))
    }
}
