import Foundation
import CoreGraphics

/// A recognized text fragment with its position on the page. Coordinates
/// are normalized 0...1 with a **top-left origin** (y increases
/// downward), so callers that start from Vision's bottom-left
/// `boundingBox` must flip y before constructing one.
struct TextBox: Equatable {
    let text: String
    let rect: CGRect
    let confidence: Float

    init(text: String, rect: CGRect, confidence: Float = 1) {
        self.text = text
        self.rect = rect
        self.confidence = confidence
    }
}

/// Orders OCR text fragments into human reading order via a recursive
/// XY-cut: repeatedly split the page along the widest empty horizontal
/// band (separating stacked blocks like a title above body text) or
/// vertical band (separating columns), then read top-to-bottom and
/// left-to-right within each leaf region. This keeps multi-column papers
/// and title-over-columns layouts readable instead of zig-zagging across
/// columns the way a naive top-to-bottom sort would.
enum ReadingOrder {
    /// Minimum normalized width of an empty band to count as a cut. Below
    /// this, ordinary inter-line / inter-word spacing would be mistaken
    /// for a structural gutter.
    static let minGap: CGFloat = 0.025

    /// Returns the boxes in reading order. Pure and deterministic.
    static func sort(_ boxes: [TextBox]) -> [TextBox] {
        xyCut(boxes)
    }

    /// Convenience: reading-ordered text joined with newlines.
    static func orderedText(_ boxes: [TextBox]) -> String {
        sort(boxes).map(\.text).joined(separator: "\n")
    }

    private static func xyCut(_ boxes: [TextBox]) -> [TextBox] {
        guard boxes.count > 1 else { return boxes }

        // A clean full-height vertical gutter means columns: peel the
        // leftmost one so each column is read top-to-bottom before moving
        // right. A full-width title spans every column, so it blocks the
        // gutter and falls through to the horizontal cut that peels it
        // off the top before the columns beneath are split.
        if let cutX = firstGap(boxes.map { ($0.rect.minX, $0.rect.maxX) }) {
            let (left, right) = partition(boxes, by: cutX) { $0.rect.midX }
            return xyCut(left) + xyCut(right)
        }
        if let cutY = firstGap(boxes.map { ($0.rect.minY, $0.rect.maxY) }) {
            let (top, bottom) = partition(boxes, by: cutY) { $0.rect.midY }
            return xyCut(top) + xyCut(bottom)
        }

        // No structural gap left: a single block. Read its lines.
        return orderLines(boxes)
    }

    /// Orders a gap-free block: group boxes into lines (vertical overlap),
    /// lines top-to-bottom, boxes within a line left-to-right.
    private static func orderLines(_ boxes: [TextBox]) -> [TextBox] {
        let sorted = boxes.sorted { $0.rect.minY < $1.rect.minY }
        var lines: [[TextBox]] = []
        for box in sorted {
            if let i = lines.firstIndex(where: { line in
                guard let ref = line.first else { return false }
                return verticalOverlap(ref.rect, box.rect) > 0.4
            }) {
                lines[i].append(box)
            } else {
                lines.append([box])
            }
        }
        return lines.flatMap { line in
            line.sorted { $0.rect.minX < $1.rect.minX }
        }
    }

    /// Fraction of the shorter box's height that overlaps vertically.
    private static func verticalOverlap(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let lo = max(a.minY, b.minY)
        let hi = min(a.maxY, b.maxY)
        let overlap = max(0, hi - lo)
        let minHeight = max(0.0001, min(a.height, b.height))
        return overlap / minHeight
    }

    private static func partition(
        _ boxes: [TextBox],
        by position: CGFloat,
        key: (TextBox) -> CGFloat
    ) -> ([TextBox], [TextBox]) {
        var below: [TextBox] = []
        var above: [TextBox] = []
        for box in boxes {
            if key(box) < position { below.append(box) } else { above.append(box) }
        }
        return (below, above)
    }

    /// Midpoint of the first interior empty band at least `minGap` wide
    /// between the projected `(lo, hi)` intervals (scanning from the low
    /// end), or nil when no such band exists. "First" rather than
    /// "widest" so a title is peeled off the top before aligned body rows
    /// are split, and the leftmost column gutter is taken first.
    private static func firstGap(_ intervals: [(CGFloat, CGFloat)]) -> CGFloat? {
        guard intervals.count > 1 else { return nil }
        let sorted = intervals.sorted { $0.0 < $1.0 }
        var coveredTo = sorted[0].1
        for (lo, hi) in sorted.dropFirst() {
            if lo - coveredTo >= minGap {
                return coveredTo + (lo - coveredTo) / 2
            }
            coveredTo = max(coveredTo, hi)
        }
        return nil
    }
}
