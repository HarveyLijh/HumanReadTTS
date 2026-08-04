import AppKit
import SwiftUI

/// A tiny, non-activating heads-up panel shown near the menu bar when
/// the user triggers "read from anywhere" while HumanReadTTS is in the
/// background. It confirms the app heard the hotkey (showing the first
/// words being read) and offers a Stop button — crucially **without
/// stealing focus** from the frontmost app, so the user stays where
/// they were.
@MainActor
final class ReadHUD {
    static let shared = ReadHUD()

    private var panel: NSPanel?
    private var dismissWork: DispatchWorkItem?

    private init() {}

    /// Show the HUD with a leading icon, a short message, and an
    /// optional Stop button. Auto-dismisses after `dismissAfter`
    /// seconds; pass `nil` to leave it up until the next call.
    func show(
        message: String,
        systemImage: String = "waveform",
        showStop: Bool,
        dismissAfter: TimeInterval?
    ) {
        let content = ReadHUDView(
            systemImage: systemImage,
            message: message,
            animated: showStop,
            onStop: showStop ? { [weak self] in
                MenuBarCommand.shared.player.stop()
                self?.dismiss()
            } : nil
        )

        let panel = ensurePanel()
        if let hosting = panel.contentView as? NSHostingView<ReadHUDView> {
            hosting.rootView = content
            let fitting = hosting.fittingSize
            panel.setContentSize(NSSize(width: 320, height: max(56, fitting.height)))
        }
        reposition(panel)
        panel.orderFrontRegardless()

        dismissWork?.cancel()
        if let dismissAfter {
            let work = DispatchWorkItem { [weak self] in self?.dismiss() }
            dismissWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + dismissAfter, execute: work)
        }
    }

    func dismiss() {
        dismissWork?.cancel()
        dismissWork = nil
        panel?.orderOut(nil)
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let hosting = NSHostingView(rootView: ReadHUDView(
            systemImage: "waveform", message: "", animated: false, onStop: nil
        ))
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 64),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [
            .canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle,
        ]
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = false
        panel.contentView = hosting
        self.panel = panel
        return panel
    }

    private func reposition(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        let margin: CGFloat = 16
        panel.setFrameOrigin(NSPoint(
            x: visible.maxX - size.width - margin,
            y: visible.maxY - size.height - margin
        ))
    }
}

private struct ReadHUDView: View {
    let systemImage: String
    let message: String
    let animated: Bool
    let onStop: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.tint)
                .symbolEffect(.variableColor.iterative, isActive: animated)

            Text(message)
                .font(.system(size: 13))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let onStop {
                Button(action: onStop) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 13, weight: .bold))
                }
                .buttonStyle(.borderless)
                .help("Stop reading")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: 320, alignment: .leading)
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.08))
        )
    }
}
