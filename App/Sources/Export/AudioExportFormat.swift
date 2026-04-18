import Foundation
import AVFoundation
import UniformTypeIdentifiers

/// Output container + codec choice for audiobook export. Two
/// formats cover every platform the user is likely to play on:
///
/// - **.m4a**: AAC-in-MP4. The modern default — small files,
///   universal playback (iTunes / Apple Music, Spotify archival
///   imports, Podcasts, any Android or Windows player built in the
///   last decade). On macOS this is the native compressed format;
///   Apple removed its MP3 encoder years ago, and m4a is the
///   drop-in replacement.
/// - **.wav**: Uncompressed Linear PCM in a RIFF wrapper. Large
///   files but zero quality loss — preferred when the user plans
///   to edit the result in an audio tool (GarageBand, Audacity,
///   Logic) or needs MP3 via an external converter. The user can
///   drag the .wav into any MP3 encoder after export.
enum AudioExportFormat: String, CaseIterable, Identifiable, Codable {
    case m4a
    case wav

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .m4a: return "M4A (AAC) — small file, universal"
        case .wav: return "WAV (uncompressed) — for editing / MP3 conversion"
        }
    }

    var fileExtension: String {
        switch self {
        case .m4a: return "m4a"
        case .wav: return "wav"
        }
    }

    var contentType: UTType {
        switch self {
        case .m4a: return .mpeg4Audio
        case .wav: return .wav
        }
    }

    /// AVAudioFile settings for writing. m4a uses AAC encoding at
    /// 64 kbps — decent quality for spoken audio without bloating
    /// the file; wav uses 16-bit Linear PCM interleaved so common
    /// audio tools can read it without a conversion step.
    func avSettings(sampleRate: Double) -> [String: Any] {
        switch self {
        case .m4a:
            return [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 64_000,
            ]
        case .wav:
            return [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsNonInterleaved: false,
            ]
        }
    }
}
