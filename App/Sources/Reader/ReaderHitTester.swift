import Foundation

/// Maps a character offset (for NSTextView readers) or a
/// page+offset pair (for PDF) to the enclosing sentence's index.
/// Binary-searched, O(log n) per hit — the reader calls it on
/// every double-click and "Read from here" right-click, so a
/// linear scan would stall a 2,000-sentence book.
///
/// The tester makes no assumptions about the blocks array — for
/// Markdown/EPUB there's a single block with blockIndex 0; for
/// PDF each page is its own block with monotonically increasing
/// (pageIndex, offsetInPage). In both cases the `Sentence` array
/// is produced by `SentenceSegmenter` in scan order, so binary
/// search against the sentence's computed absolute start works.
enum ReaderHitTester {
    /// For single-block readers (Markdown, EPUB). `offset` is a
    /// UTF-16 index into the rendered plain text. Returns `nil`
    /// when `offset` falls outside every sentence (e.g. in a
    /// block-boundary `\n\n` the segmenter skipped).
    static func sentenceIndex(
        forOffset offset: Int, in sentences: [Sentence]
    ) -> Int? {
        guard !sentences.isEmpty else { return nil }
        // All sentences share blockIndex=0, so offsetInBlock is
        // the absolute offset. Bisect to the last sentence whose
        // start <= offset; accept iff offset is inside its range.
        var lo = 0
        var hi = sentences.count - 1
        var candidate: Int?
        while lo <= hi {
            let mid = (lo + hi) / 2
            let start = sentences[mid].offsetInBlock
            if start <= offset {
                candidate = mid
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }
        guard let idx = candidate else { return nil }
        let s = sentences[idx]
        let end = s.offsetInBlock + s.lengthInBlock
        return offset < end ? idx : nil
    }

    /// For PDF readers. `pageOffset` is a UTF-16 index into the
    /// given page's extracted `page.string`. The caller passes the
    /// `blocks` array the extractor produced so we can recover
    /// each sentence's absolute page coordinates. Blocks are
    /// page-scoped — a sentence is on page P iff its
    /// `blocks[blockIndex].pageIndex == P`.
    static func sentenceIndex(
        forPageOffset pageOffset: Int,
        pageIndex: Int,
        sentences: [Sentence],
        blocks: [DocumentBlock]
    ) -> Int? {
        guard !sentences.isEmpty, !blocks.isEmpty else { return nil }
        // Find the contiguous sentence range that lives on this page.
        // SentenceSegmenter emits sentences in block order, and blocks
        // are in page order, so a linear narrow-down is fine — but we
        // use a binary search by (pageIndex, pageOffset) anyway, since
        // documents can have thousands of sentences.
        var lo = 0
        var hi = sentences.count - 1
        var candidate: Int?
        while lo <= hi {
            let mid = (lo + hi) / 2
            let s = sentences[mid]
            guard s.blockIndex < blocks.count else { return nil }
            let block = blocks[s.blockIndex]
            let page = block.pageIndex
            let start = block.offsetInPage + s.offsetInBlock
            // Sort key: (pageIndex, startOffset).
            if page < pageIndex || (page == pageIndex && start <= pageOffset) {
                candidate = mid
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }
        guard let idx = candidate else { return nil }
        let s = sentences[idx]
        let block = blocks[s.blockIndex]
        guard block.pageIndex == pageIndex else { return nil }
        let start = block.offsetInPage + s.offsetInBlock
        let end = start + s.lengthInBlock
        return pageOffset < end ? idx : nil
    }
}
