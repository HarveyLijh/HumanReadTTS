import XCTest
import AppKit
@testable import HumanReadTTS

final class HighlightStyleTests: XCTestCase {

    func test_defaultOpacity_reproducesLegacyAlphas() {
        // The old hard-coded recipe was sentence 0.25 / word 0.55.
        let style = HighlightStyle.make(palette: .teal, opacity: 0.25)
        XCTAssertEqual(Double(style.sentenceBand.alphaComponent), 0.25, accuracy: 0.0001)
        XCTAssertEqual(Double(style.activeWord.alphaComponent), 0.55, accuracy: 0.0001,
                       "active word must stay wordBoost (0.30) above the sentence band")
    }

    func test_tealBaseMatchesLegacyAccent() {
        let base = HighlightPalette.teal.baseColor.usingColorSpace(.sRGB)!
        XCTAssertEqual(Double(base.redComponent),   Double(0x5B) / 255, accuracy: 0.001)
        XCTAssertEqual(Double(base.greenComponent), Double(0xB8) / 255, accuracy: 0.001)
        XCTAssertEqual(Double(base.blueComponent),  Double(0xC4) / 255, accuracy: 0.001)
    }

    func test_opacityClampedToLegibleRange() {
        XCTAssertEqual(Double(HighlightStyle.make(palette: .teal, opacity: 0.0).sentenceBand.alphaComponent),
                       HighlightStyle.minOpacity, accuracy: 0.0001)
        XCTAssertEqual(Double(HighlightStyle.make(palette: .teal, opacity: 1.0).sentenceBand.alphaComponent),
                       HighlightStyle.maxOpacity, accuracy: 0.0001)
    }

    func test_wordBandCapsBelowOpaque() {
        // sentence 0.7 + 0.30 boost would be 1.0; capped at 0.9.
        let style = HighlightStyle.make(palette: .teal, opacity: 0.7)
        XCTAssertEqual(Double(style.activeWord.alphaComponent), 0.9, accuracy: 0.0001)
    }

    func test_palettesAreVisuallyDistinct() {
        let cases = HighlightPalette.allCases
        let bases = cases.map { $0.baseColor.usingColorSpace(.sRGB)! }
        for i in bases.indices {
            for j in bases.indices where j > i {
                let a = bases[i], b = bases[j]
                let distance = abs(Double(a.redComponent - b.redComponent))
                    + abs(Double(a.greenComponent - b.greenComponent))
                    + abs(Double(a.blueComponent - b.blueComponent))
                XCTAssertGreaterThan(distance, 0.10,
                    "palettes \(cases[i]) and \(cases[j]) are too similar to tell apart")
            }
        }
    }
}
