import XCTest
import AppKit
@testable import ReadAloudTTS

@MainActor
final class ReaderTypographyTests: XCTestCase {

    // MARK: - ReaderFontFace

    func test_baseFont_neverNil_andHonorsSize() {
        for face in ReaderFontFace.allCases {
            let font = face.baseFont(size: 18)
            XCTAssertEqual(font.pointSize, 18, accuracy: 0.01,
                           "\(face) must produce the requested point size")
        }
    }

    func test_serif_prefersNewYorkWhenInstalled() {
        // New York is the historic reader face. Where it's installed the
        // serif option must resolve to it; in a stripped environment the
        // fallback must still be a usable font at the requested size.
        let font = ReaderFontFace.serif.baseFont(size: 16)
        if NSFont(name: "New York", size: 16) != nil {
            XCTAssertTrue(font.familyName?.contains("New York") ?? false,
                          "serif should map to New York, got \(font.familyName ?? "nil")")
        } else {
            XCTAssertEqual(font.pointSize, 16, accuracy: 0.01)
        }
    }

    func test_isBundled_onlyForAccessibilityFaces() {
        XCTAssertTrue(ReaderFontFace.openDyslexic.isBundled)
        XCTAssertTrue(ReaderFontFace.atkinsonHyperlegible.isBundled)
        XCTAssertFalse(ReaderFontFace.serif.isBundled)
        XCTAssertFalse(ReaderFontFace.system.isBundled)
        XCTAssertFalse(ReaderFontFace.monospaced.isBundled)
    }

    func test_everyFace_hasNonEmptyDisplayName() {
        for face in ReaderFontFace.allCases {
            XCTAssertFalse(face.displayName.isEmpty)
        }
    }

    func test_subtitle_presentOnlyForBundledFaces() {
        for face in ReaderFontFace.allCases {
            XCTAssertEqual(face.subtitle != nil, face.isBundled,
                           "\(face) subtitle presence should match isBundled")
        }
    }

    // MARK: - ReaderTypography

    func test_default_reproducesLegacyLook() {
        let t = ReaderTypography()
        XCTAssertEqual(t.face, .serif)
        XCTAssertEqual(t.lineHeightMultiple, 1.25, accuracy: 0.0001)
        XCTAssertNil(t.kern, "default reading must emit no kern attribute")
    }

    func test_kern_isNilWhenZero_andValueOtherwise() {
        XCTAssertNil(ReaderTypography(letterSpacing: 0).kern)
        XCTAssertEqual(ReaderTypography(letterSpacing: 1.5).kern, 1.5)
    }

    func test_paragraphStyle_carriesLineHeightAndSpacing() {
        let style = ReaderTypography(lineHeightMultiple: 1.8).paragraphStyle(paragraphSpacing: 6)
        XCTAssertEqual(style.lineHeightMultiple, 1.8, accuracy: 0.0001)
        XCTAssertEqual(style.paragraphSpacing, 6, accuracy: 0.0001)
    }

    func test_initFromSettings_copiesAllKnobs() {
        let settings = ReaderSettings(defaults: ephemeralDefaults())
        settings.fontFace = .openDyslexic
        settings.lineSpacingMultiple = 1.6
        settings.letterSpacing = 0.8
        let t = ReaderTypography(from: settings)
        XCTAssertEqual(t.face, .openDyslexic)
        XCTAssertEqual(t.lineHeightMultiple, 1.6, accuracy: 0.0001)
        XCTAssertEqual(t.letterSpacing, 0.8, accuracy: 0.0001)
    }

    // MARK: - ReaderSettings persistence + clamps

    func test_settings_persistFaceAndSpacing() {
        let defaults = ephemeralDefaults()
        let first = ReaderSettings(defaults: defaults)
        first.fontFace = .atkinsonHyperlegible
        first.lineSpacingMultiple = 1.5
        first.letterSpacing = 1.0

        let reloaded = ReaderSettings(defaults: defaults)
        XCTAssertEqual(reloaded.fontFace, .atkinsonHyperlegible)
        XCTAssertEqual(reloaded.lineSpacingMultiple, 1.5, accuracy: 0.0001)
        XCTAssertEqual(reloaded.letterSpacing, 1.0, accuracy: 0.0001)
    }

    func test_lineSpacing_clampsToReadableRange() {
        let s = ReaderSettings(defaults: ephemeralDefaults())
        s.lineSpacingMultiple = 10
        XCTAssertEqual(s.lineSpacingMultiple, 2.2, accuracy: 0.0001)
        s.lineSpacingMultiple = 0.1
        XCTAssertEqual(s.lineSpacingMultiple, 1.0, accuracy: 0.0001)
    }

    func test_letterSpacing_clampsToReadableRange() {
        let s = ReaderSettings(defaults: ephemeralDefaults())
        s.letterSpacing = 99
        XCTAssertEqual(s.letterSpacing, 2.5, accuracy: 0.0001)
        s.letterSpacing = -5
        XCTAssertEqual(s.letterSpacing, 0, accuracy: 0.0001)
    }

    func test_reset_restoresTypographyDefaults() {
        let s = ReaderSettings(defaults: ephemeralDefaults())
        s.fontFace = .openDyslexic
        s.lineSpacingMultiple = 2.0
        s.letterSpacing = 2.0
        s.reset()
        XCTAssertEqual(s.fontFace, .serif)
        XCTAssertEqual(s.lineSpacingMultiple, 1.25, accuracy: 0.0001)
        XCTAssertEqual(s.letterSpacing, 0, accuracy: 0.0001)
    }

    // MARK: - Bundled font registration

    func test_registerBundledFonts_isIdempotent() {
        // Should not crash or throw when called repeatedly.
        ReaderFonts.registerBundledFonts()
        ReaderFonts.registerBundledFonts()
    }

    // MARK: - Helpers

    private func ephemeralDefaults() -> UserDefaults {
        let suite = "test.readertypography.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }
}
