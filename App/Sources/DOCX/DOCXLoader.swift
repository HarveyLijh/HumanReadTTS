import Foundation
import AppKit
import ZIPFoundation
import os

/// Extracts readable prose from a `.docx` (Office Open XML) archive
/// and renders it as a single `NSAttributedString`.
///
/// Happy path:
/// 1. Open the .docx as a ZIP archive.
/// 2. Read `word/document.xml` (the main body part).
/// 3. Walk `<w:body>` for paragraphs (`<w:p>`) → table rows (`<w:tr>`)
///    and runs (`<w:r>`), translating each run's `<w:rPr>` flags
///    (`<w:b>`, `<w:i>`, headings via `<w:pStyle w:val="Heading…">`)
///    into NSFont / NSColor attributes.
/// 4. Join paragraphs with `\n\n` so the downstream
///    `SentenceSegmenter` sees natural block boundaries.
///
/// Out of scope: footnotes, embedded images, comments, revision
/// tracking, numbered/bulleted list rendering (numbers themselves
/// aren't in document.xml — they live in numbering.xml and are
/// resolved at render time). The text content of list items still
/// gets read; only the bullet glyph / "1." prefix is dropped. That's
/// acceptable for a TTS reader where the speech doesn't need the
/// glyph anyway.
enum DOCXLoader {
    enum LoadError: LocalizedError {
        case notReadable
        case documentMissing
        case empty

        var errorDescription: String? {
            switch self {
            case .notReadable: return "Couldn't read the DOCX file."
            case .documentMissing: return "DOCX is missing word/document.xml."
            case .empty: return "DOCX has no readable text."
            }
        }
    }

    private static let log = Logger(subsystem: "app.readaloudtts.mac", category: "docx")

    @MainActor
    static func load(url: URL) async throws -> NSAttributedString {
        try loadSync(url: url)
    }

    @MainActor
    static func loadSync(url: URL) throws -> NSAttributedString {
        let archive: Archive
        do {
            archive = try Archive(url: url, accessMode: .read)
        } catch {
            throw LoadError.notReadable
        }

        guard let documentEntry = archive["word/document.xml"] else {
            throw LoadError.documentMissing
        }
        let data = try extract(archive: archive, entry: documentEntry)

        let parser = DocumentXMLParser()
        guard parser.parse(data: data) else {
            throw LoadError.notReadable
        }
        guard !parser.paragraphs.isEmpty else {
            throw LoadError.empty
        }

        return render(paragraphs: parser.paragraphs)
    }

    private static func extract(archive: Archive, entry: Entry) throws -> Data {
        var data = Data()
        _ = try archive.extract(entry) { chunk in data.append(chunk) }
        return data
    }

    /// Builds the visible `NSAttributedString` from the parsed
    /// paragraphs. Pulled out of `loadSync` so the XML parser stays
    /// purely structural and the rendering rules — font sizes,
    /// heading boldness, paragraph spacing — live in one place.
    private static func render(paragraphs: [Paragraph]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let bodyFont = NSFont(name: "New York", size: 16)
            ?? NSFont.systemFont(ofSize: 16)
        let bodyAttrs: [NSAttributedString.Key: Any] = [
            .font: bodyFont,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: standardParagraphStyle(),
        ]

        for (index, paragraph) in paragraphs.enumerated() {
            // Skip empty paragraphs in the middle of the document so a
            // long stretch of blank-line padding from the editor
            // doesn't create N×N text storage cells in the renderer;
            // we still emit one `\n\n` between adjacent paragraphs, so
            // logical spacing is preserved.
            if paragraph.runs.isEmpty {
                if index < paragraphs.count - 1 {
                    result.append(NSAttributedString(
                        string: "\n", attributes: bodyAttrs
                    ))
                }
                continue
            }

            for run in paragraph.runs {
                let runAttrs = attributes(
                    for: run,
                    style: paragraph.style,
                    base: bodyAttrs
                )
                // Word stores newlines as `<w:br/>` rather than \n
                // inside `<w:t>`; the parser already translated those
                // into "\n", so the attributed run can append unchanged.
                result.append(NSAttributedString(string: run.text, attributes: runAttrs))
            }

            if index < paragraphs.count - 1 {
                result.append(NSAttributedString(
                    string: "\n\n", attributes: bodyAttrs
                ))
            }
        }

        return result
    }

    private static func attributes(
        for run: Run,
        style: ParagraphStyle,
        base: [NSAttributedString.Key: Any]
    ) -> [NSAttributedString.Key: Any] {
        var attrs = base
        let manager = NSFontManager.shared

        // Block-style overrides come first so inline italic on a
        // heading still applies on top of the heading font.
        switch style {
        case .heading(let level):
            let size: CGFloat = {
                switch level {
                case 1: return 28
                case 2: return 22
                case 3: return 18
                default: return 16
                }
            }()
            let base = NSFont(name: "New York", size: size)
                ?? NSFont.systemFont(ofSize: size)
            attrs[.font] = manager.convert(base, toHaveTrait: .boldFontMask)
        case .body:
            break
        }

        if run.isBold || run.isItalic {
            let current = attrs[.font] as? NSFont
                ?? NSFont(name: "New York", size: 16)
                ?? NSFont.systemFont(ofSize: 16)
            var traits = manager.traits(of: current)
            if run.isBold { traits.insert(.boldFontMask) }
            if run.isItalic { traits.insert(.italicFontMask) }
            attrs[.font] = manager.convert(current, toHaveTrait: traits)
        }
        return attrs
    }

    private static func standardParagraphStyle() -> NSParagraphStyle {
        let para = NSMutableParagraphStyle()
        para.lineHeightMultiple = 1.25
        para.paragraphSpacing = 6
        return para
    }

    // MARK: - Parsed model

    fileprivate struct Run {
        var text: String
        var isBold: Bool
        var isItalic: Bool
    }

    fileprivate enum ParagraphStyle: Equatable {
        case body
        case heading(Int)
    }

    fileprivate struct Paragraph {
        var runs: [Run]
        var style: ParagraphStyle
    }
}

// MARK: - XML parser

/// Streaming parser for `word/document.xml`. Avoids loading the whole
/// DOM the way XMLDocument would, which keeps memory low on very long
/// papers and lets us bail early if the file is malformed.
private final class DocumentXMLParser: NSObject, XMLParserDelegate {
    var paragraphs: [DOCXLoader.Paragraph] = []

    private var currentParagraphRuns: [DOCXLoader.Run] = []
    private var currentParagraphStyle: DOCXLoader.ParagraphStyle = .body

    /// Run-level state. We hold the in-progress run as `var` fields so
    /// nested `<w:rPr>` toggles and `<w:t>` text accumulation flow
    /// into the same struct, then the run is flushed on `</w:r>`.
    private var currentRunText: String = ""
    private var currentRunIsBold: Bool = false
    private var currentRunIsItalic: Bool = false
    private var insideRun: Bool = false
    private var insideText: Bool = false
    private var insideRunProperties: Bool = false
    private var insideParagraphProperties: Bool = false

    func parse(data: Data) -> Bool {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.shouldProcessNamespaces = false
        parser.shouldReportNamespacePrefixes = false
        return parser.parse()
    }

    // MARK: XMLParserDelegate

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        switch elementName {
        case "w:p":
            currentParagraphRuns = []
            currentParagraphStyle = .body
        case "w:pPr":
            insideParagraphProperties = true
        case "w:pStyle":
            if insideParagraphProperties,
               let val = attributeDict["w:val"]?.lowercased() {
                currentParagraphStyle = headingStyle(from: val)
            }
        case "w:r":
            insideRun = true
            currentRunText = ""
            currentRunIsBold = false
            currentRunIsItalic = false
        case "w:rPr":
            insideRunProperties = true
        case "w:b":
            if insideRunProperties {
                currentRunIsBold = !isExplicitlyFalse(attributeDict["w:val"])
            }
        case "w:i":
            if insideRunProperties {
                currentRunIsItalic = !isExplicitlyFalse(attributeDict["w:val"])
            }
        case "w:t":
            if insideRun {
                insideText = true
            }
        case "w:tab":
            if insideRun { currentRunText.append("\t") }
        case "w:br", "w:cr":
            if insideRun { currentRunText.append("\n") }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        switch elementName {
        case "w:pPr":
            insideParagraphProperties = false
        case "w:rPr":
            insideRunProperties = false
        case "w:t":
            insideText = false
        case "w:r":
            insideRun = false
            if !currentRunText.isEmpty {
                currentParagraphRuns.append(DOCXLoader.Run(
                    text: currentRunText,
                    isBold: currentRunIsBold,
                    isItalic: currentRunIsItalic
                ))
            }
            currentRunText = ""
        case "w:p":
            paragraphs.append(DOCXLoader.Paragraph(
                runs: currentParagraphRuns,
                style: currentParagraphStyle
            ))
            currentParagraphRuns = []
            currentParagraphStyle = .body
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard insideText else { return }
        currentRunText.append(string)
    }

    func parser(_ parser: XMLParser, foundIgnorableWhitespace whitespaceString: String) {
        guard insideText else { return }
        currentRunText.append(whitespaceString)
    }

    // MARK: helpers

    private func headingStyle(from value: String) -> DOCXLoader.ParagraphStyle {
        // Word's default English template uses `Heading1` / `Heading2`
        // / `Title`. Localized templates rename but Office still keeps
        // the digit suffix, so a name that contains "heading" or
        // "title" + trailing digit is good enough for the common case.
        guard value.contains("heading") || value.contains("title") else {
            return .body
        }
        if let lastChar = value.last, let level = lastChar.wholeNumberValue {
            return .heading(min(max(level, 1), 6))
        }
        return .heading(1)
    }

    private func isExplicitlyFalse(_ value: String?) -> Bool {
        guard let value = value?.lowercased() else { return false }
        return value == "0" || value == "false" || value == "off"
    }
}
