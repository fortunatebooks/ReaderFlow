import Foundation
@testable import ReaderFlow
import Testing

struct ExcerptReaderNavigationTests {
    @Test func decodesStoredLocatorForReaderJump() throws {
        let locator = ReaderLocator(
            bookId: UUID(),
            bookFingerprint: "fingerprint",
            spineIndex: 2,
            href: "chapter3.xhtml",
            chapterTitle: "Chapter 3",
            chapterProgression: 0.4,
            totalProgression: 0.58,
            scrollY: 1200,
            documentHeight: 3000,
            textQuote: nil,
            domTextPath: nil,
            contentHash: nil,
            readiumLocatorJSON: nil,
            createdAt: Date(timeIntervalSinceReferenceDate: 100)
        )
        let data = try JSONEncoder().encode(locator)
        let excerpt = ExcerptEntity(
            bookId: locator.bookId,
            bookTitleSnapshot: "Book",
            authorDisplaySnapshot: "Author",
            selectedText: "Selected text",
            locatorJSON: data,
            sortProgress: 0.1
        )

        #expect(excerpt.readerLocator?.href == "chapter3.xhtml")
        #expect(excerpt.readerLocator?.chapterTitle == "Chapter 3")
        #expect(excerpt.readerInitialPosition.href == "chapter3.xhtml")
        #expect(abs((excerpt.readerInitialPosition.chapterProgression ?? 0) - 0.4) < 0.0001)
        #expect(abs(excerpt.readerJumpProgress - 0.58) < 0.0001)
    }

    @Test func fallsBackToBoundedSortProgressWhenLocatorIsMissing() {
        let highExcerpt = ExcerptEntity(
            bookId: UUID(),
            bookTitleSnapshot: "Book",
            authorDisplaySnapshot: "Author",
            selectedText: "Selected text",
            sortProgress: 1.8
        )
        let lowExcerpt = ExcerptEntity(
            bookId: UUID(),
            bookTitleSnapshot: "Book",
            authorDisplaySnapshot: "Author",
            selectedText: "Selected text",
            sortProgress: -0.4
        )

        #expect(highExcerpt.readerLocator == nil)
        #expect(highExcerpt.readerJumpProgress == 1)
        #expect(highExcerpt.readerInitialPosition.href == nil)
        #expect(highExcerpt.readerInitialPosition.chapterProgression == nil)
        #expect(lowExcerpt.readerJumpProgress == 0)
    }
}
