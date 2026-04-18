import SwiftUI
import AppKit

/// Wraps `NSVisualEffectView` so SwiftUI surfaces can opt into the
/// behind-window vibrancy Apple uses in Mail, Notes, and Finder.
/// Prefer `.behindWindow` blending + `.active` state so the effect
/// persists when the window is inactive — matches system apps.
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .underWindowBackground
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var isEmphasized: Bool = false

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.isEmphasized = isEmphasized
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blendingMode
        view.isEmphasized = isEmphasized
    }
}

/// Runs a closure against the hosting `NSWindow` once it's attached.
/// Used for chrome tweaks (hiding the title bar, making the window
/// movable by background) that SwiftUI doesn't yet expose natively.
struct WindowAccessor: NSViewRepresentable {
    let configure: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view] in
            guard let window = view?.window else { return }
            configure(window)
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { [weak view] in
            guard let window = view?.window else { return }
            configure(window)
        }
    }
}
