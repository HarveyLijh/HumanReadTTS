import Vision
import CoreGraphics
import Foundation

enum OCRError: Error {
    /// Vision finished but found no text.
    case noText
}

/// On-device text recognition. Wraps Vision's `VNRecognizeTextRequest`,
/// converts each observation into a top-left-origin ``TextBox``, and hands
/// the set to ``ReadingOrder`` so multi-column and title-over-body layouts
/// come back in human reading order rather than raster order.
///
/// Stateless and `Sendable`; the recognition methods are `nonisolated`
/// async, so Vision's blocking `perform` runs off the main actor.
struct OCRService: Sendable {
    static let shared = OCRService()

    /// Recognized text in reading order, joined by newlines. Throws
    /// ``OCRError/noText`` when nothing legible is found.
    func recognizeText(in image: CGImage, languages: [String] = []) async throws -> String {
        let boxes = try await recognizeBoxes(in: image, languages: languages)
        guard !boxes.isEmpty else { throw OCRError.noText }
        return ReadingOrder.orderedText(boxes)
    }

    /// Recognized fragments with normalized top-left-origin rects, ready
    /// for ``ReadingOrder``. Empty when the page has no text.
    func recognizeBoxes(in image: CGImage, languages: [String] = []) async throws -> [TextBox] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        if !languages.isEmpty {
            request.recognitionLanguages = languages
        }

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])

        let observations = request.results ?? []
        return observations.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            // Vision's boundingBox is normalized with a bottom-left origin;
            // TextBox wants top-left, so flip y.
            let box = observation.boundingBox
            let rect = CGRect(
                x: box.minX,
                y: 1 - box.maxY,
                width: box.width,
                height: box.height
            )
            return TextBox(text: candidate.string, rect: rect, confidence: candidate.confidence)
        }
    }
}
