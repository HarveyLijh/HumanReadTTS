import Foundation

/// Materialises `WelcomeSample.md` into a real on-disk file the
/// rest of the app can treat like any other document — the
/// Library records it via `record(url:)`, the viewer opens it
/// via `DroppedDocument(url:)`, resume position persists per
/// the usual path. Keeping it out of the read-only app bundle
/// means the user can actually scroll and leave bookmarks in it
/// without sandbox complaints.
///
/// The copy lives under Application Support rather than a temp
/// directory so it survives restarts, and reopening the sample
/// from the sidebar continues to work after the first onboarding
/// run completes.
enum OnboardingSampleLoader {
    /// User-visible filename. Shown in the sidebar, the window
    /// title, and the resume position database, so we pick a
    /// name that reads well in those surfaces — "Welcome to
    /// ReadAloudTTS.md" rather than the internal bundle name.
    static let filename = "Welcome to ReadAloudTTS.md"

    enum LoadError: Error {
        case resourceMissing
        case destinationUnavailable
    }

    /// Copy the bundled sample into Application Support (if not
    /// already present) and return its URL. Idempotent: a second
    /// call returns the existing copy without overwriting, so
    /// any annotations or scroll state the user left there
    /// stick.
    ///
    /// If you need to re-seed after editing `WelcomeSample.md`
    /// during development, delete the file from Application
    /// Support (or bump a manual re-seed key); callers should
    /// not pass `overwrite=true` in production because that
    /// destroys user edits.
    static func prepareSampleURL(overwrite: Bool = false) throws -> URL {
        guard let bundled = Bundle.main.url(
            forResource: "WelcomeSample", withExtension: "md"
        ) else {
            throw LoadError.resourceMissing
        }

        let supportDir = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let readAloudTTSDir = supportDir.appendingPathComponent("ReadAloudTTS", isDirectory: true)
        if !FileManager.default.fileExists(atPath: readAloudTTSDir.path) {
            try FileManager.default.createDirectory(
                at: readAloudTTSDir, withIntermediateDirectories: true
            )
        }

        let destination = readAloudTTSDir.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: destination.path) {
            if overwrite {
                try FileManager.default.removeItem(at: destination)
            } else {
                return destination
            }
        }

        try FileManager.default.copyItem(at: bundled, to: destination)
        return destination
    }
}
