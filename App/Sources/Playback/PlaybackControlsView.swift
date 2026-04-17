import SwiftUI

/// A single circular play/pause button in `Color.rheaAccent`. The
/// keyboard shortcut and richer transport controls land with the
/// menu work in M2.6.
struct PlaybackControlsView: View {
    let player: SpeechPlayer

    var body: some View {
        Button {
            player.togglePlayPause()
        } label: {
            Image(systemName: iconName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Color.rheaAccent, in: Circle())
                .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
        .disabled(player.sentences.isEmpty)
        .opacity(player.sentences.isEmpty ? 0.4 : 1)
        .help(helpText)
    }

    private var iconName: String {
        player.state.isPlaying ? "pause.fill" : "play.fill"
    }

    private var helpText: String {
        switch player.state {
        case .idle: return "Play"
        case .playing: return "Pause"
        case .paused: return "Resume"
        }
    }
}
