import XCTest
@testable import ReadAloudTTS

@MainActor
final class ReadingQueueTests: XCTestCase {

    private func makeQueue() -> ReadingQueue {
        let q = ReadingQueue.shared
        q.clear()
        q.autoAdvance = true
        return q
    }

    func test_enqueue_appendsAndReturnsItem() {
        let q = makeQueue()
        let item = q.enqueue("First article body.")
        XCTAssertNotNil(item)
        XCTAssertEqual(q.count, 1)
        XCTAssertEqual(q.items.first?.text, "First article body.")
    }

    func test_enqueue_ignoresEmptyOrWhitespace() {
        let q = makeQueue()
        XCTAssertNil(q.enqueue(""))
        XCTAssertNil(q.enqueue("   \n  "))
        XCTAssertTrue(q.isEmpty)
    }

    func test_enqueue_derivesTitleFromText() {
        let q = makeQueue()
        let item = q.enqueue("The quick brown fox jumps over the lazy dog and keeps running far.")
        XCTAssertNotNil(item?.title)
        XCTAssertTrue(item!.title.hasSuffix("…"), "long titles are truncated")
        XCTAssertLessThanOrEqual(item!.title.count, 43)
    }

    func test_enqueue_usesExplicitTitleWhenGiven() {
        let q = makeQueue()
        let item = q.enqueue("body", title: "Chapter 1")
        XCTAssertEqual(item?.title, "Chapter 1")
    }

    func test_dequeueNext_isFIFO_andNilWhenEmpty() {
        let q = makeQueue()
        q.enqueue("one", title: "1")
        q.enqueue("two", title: "2")
        XCTAssertEqual(q.dequeueNext()?.title, "1")
        XCTAssertEqual(q.dequeueNext()?.title, "2")
        XCTAssertNil(q.dequeueNext())
        XCTAssertTrue(q.isEmpty)
    }

    func test_remove_byID() {
        let q = makeQueue()
        let a = q.enqueue("a", title: "A")!
        q.enqueue("b", title: "B")
        q.remove(a.id)
        XCTAssertEqual(q.count, 1)
        XCTAssertEqual(q.items.first?.title, "B")
    }

    func test_clear_emptiesQueue() {
        let q = makeQueue()
        q.enqueue("a")
        q.enqueue("b")
        q.clear()
        XCTAssertTrue(q.isEmpty)
    }

    func test_derivedTitle_shortTextUnchanged() {
        XCTAssertEqual(ReadingQueue.derivedTitle(from: "Short one"), "Short one")
        XCTAssertEqual(ReadingQueue.derivedTitle(from: "  collapse\nnewlines  "), "collapse newlines")
    }
}
