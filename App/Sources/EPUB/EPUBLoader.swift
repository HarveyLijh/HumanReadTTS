import Foundation
import AppKit
import ZIPFoundation
import os

/// Parses an EPUB (ZIP of XHTML) and renders its spine into a
/// single `NSAttributedString`.
///
/// Happy path:
/// 1. Open the .epub as a ZIP archive.
/// 2. Read META-INF/container.xml → find the OPF path.
/// 3. Read the OPF → build a manifest (id → href) and the spine
///    (ordered list of idrefs).
/// 4. For each spine entry, read its XHTML body and convert via
///    `NSAttributedString(data:options:documentAttributes:)` with
///    `documentType: .html`. Append to the combined string with
///    a chapter separator.
///
/// Out of scope: TOC navigation, images, embedded CSS overrides,
/// DRM. First cut renders the prose in source order.
enum EPUBLoader {
    enum LoadError: LocalizedError {
        case notReadable
        case containerMissing
        case opfMissing(String)
        case empty

        var errorDescription: String? {
            switch self {
            case .notReadable: return "Couldn't read the EPUB file."
            case .containerMissing: return "EPUB is missing META-INF/container.xml."
            case .opfMissing(let p): return "EPUB's root file \(p) is missing."
            case .empty: return "EPUB has no readable chapters."
            }
        }
    }

    private static let log = Logger(subsystem: "app.rhea.mac", category: "epub")

    @MainActor
    static func load(url: URL) async throws -> NSAttributedString {
        // NSAttributedString HTML parsing is main-actor-constrained
        // on modern macOS, and NSAttributedString isn't Sendable
        // so we can't ferry it across actor boundaries. Call
        // synchronously on the main actor and accept the brief
        // UI pause for medium-size EPUBs. The async signature is
        // preserved so callers can upgrade to a background
        // implementation later without changing call sites.
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

        guard let containerEntry = archive["META-INF/container.xml"] else {
            throw LoadError.containerMissing
        }
        let containerData = try extract(archive: archive, entry: containerEntry)

        let rootPath = parseContainerRoot(containerData) ?? "content.opf"

        guard let opfEntry = archive[rootPath] else {
            throw LoadError.opfMissing(rootPath)
        }
        let opfData = try extract(archive: archive, entry: opfEntry)

        let spineHrefs = parseSpineHrefs(opfData)
        let baseDir = (rootPath as NSString).deletingLastPathComponent

        let combined = NSMutableAttributedString()
        var chapterCount = 0
        for (index, href) in spineHrefs.enumerated() {
            let fullPath = baseDir.isEmpty ? href : "\(baseDir)/\(href)"
            guard let entry = archive[fullPath] else { continue }
            let data = (try? extract(archive: archive, entry: entry)) ?? Data()

            do {
                let chapter = try NSAttributedString(
                    data: data,
                    options: [
                        .documentType: NSAttributedString.DocumentType.html,
                        .characterEncoding: String.Encoding.utf8.rawValue
                    ],
                    documentAttributes: nil
                )
                combined.append(chapter)
                if index < spineHrefs.count - 1 {
                    combined.append(NSAttributedString(string: "\n\n\n"))
                }
                chapterCount += 1
            } catch {
                Self.log.error("chapter parse failed for \(fullPath, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }

        guard combined.length > 0, chapterCount > 0 else {
            throw LoadError.empty
        }

        Self.log.info("loaded EPUB with \(chapterCount) chapters, \(combined.length) chars")
        return combined
    }

    // MARK: zip helpers

    private static func extract(archive: Archive, entry: Entry) throws -> Data {
        var buffer = Data()
        _ = try archive.extract(entry) { chunk in buffer.append(chunk) }
        return buffer
    }

    // MARK: XML parsers

    private static func parseContainerRoot(_ data: Data) -> String? {
        let delegate = ContainerDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.rootPath
    }

    private static func parseSpineHrefs(_ data: Data) -> [String] {
        let delegate = OPFDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.spineHrefs()
    }

    private final class ContainerDelegate: NSObject, XMLParserDelegate {
        var rootPath: String?

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes attributeDict: [String: String]
        ) {
            if elementName.hasSuffix("rootfile"),
               let path = attributeDict["full-path"] {
                rootPath = path
            }
        }
    }

    private final class OPFDelegate: NSObject, XMLParserDelegate {
        private var manifest: [String: String] = [:]
        private var spineOrder: [String] = []
        private var insideSpine = false

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes attributeDict: [String: String]
        ) {
            let name = elementName.components(separatedBy: ":").last ?? elementName
            if name == "item",
               let id = attributeDict["id"],
               let href = attributeDict["href"] {
                manifest[id] = href
            }
            if name == "spine" { insideSpine = true }
            if insideSpine,
               name == "itemref",
               let idref = attributeDict["idref"] {
                spineOrder.append(idref)
            }
        }

        func parser(
            _ parser: XMLParser,
            didEndElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?
        ) {
            let name = elementName.components(separatedBy: ":").last ?? elementName
            if name == "spine" { insideSpine = false }
        }

        func spineHrefs() -> [String] {
            spineOrder.compactMap { manifest[$0] }
        }
    }
}
