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
        #expect(abs((excerpt.readerInitialPosition.scrollY ?? 0) - 1200) < 0.0001)
        #expect(abs((excerpt.readerInitialPosition.documentHeight ?? 0) - 3000) < 0.0001)
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

    @Test func bookInitialPositionUsesMatchingStoredLocator() throws {
        let bookId = UUID()
        let locator = ReaderLocator(
            bookId: bookId,
            bookFingerprint: "fingerprint",
            spineIndex: 3,
            href: "Text/chapter4.xhtml",
            chapterTitle: "Chapter 4",
            chapterProgression: 0.32,
            totalProgression: 0.71,
            scrollY: 1600,
            documentHeight: 4200,
            textQuote: nil,
            domTextPath: nil,
            contentHash: nil,
            readiumLocatorJSON: nil,
            createdAt: Date(timeIntervalSinceReferenceDate: 200)
        )
        let book = try BookEntity(
            id: bookId,
            title: "Book",
            originalFileName: "book.epub",
            readingProgress: 0.2,
            lastLocatorJSON: JSONEncoder().encode(locator),
            contentFingerprint: "fingerprint"
        )

        #expect(book.readerLocator?.spineIndex == 3)
        #expect(book.readerInitialPosition?.href == "Text/chapter4.xhtml")
        #expect(abs((book.readerInitialPosition?.progress ?? 0) - 0.71) < 0.0001)
        #expect(abs((book.readerInitialPosition?.chapterProgression ?? 0) - 0.32) < 0.0001)
        #expect(abs((book.readerInitialPosition?.scrollY ?? 0) - 1600) < 0.0001)
        #expect(abs((book.readerInitialPosition?.documentHeight ?? 0) - 4200) < 0.0001)
    }

    @Test func bookInitialPositionRejectsMismatchedStoredLocator() throws {
        let bookId = UUID()
        let locator = ReaderLocator(
            bookId: bookId,
            bookFingerprint: "old-fingerprint",
            spineIndex: 0,
            href: "chapter.xhtml",
            chapterTitle: nil,
            chapterProgression: 0.5,
            totalProgression: 0.5,
            scrollY: 500,
            documentHeight: 1000,
            textQuote: nil,
            domTextPath: nil,
            contentHash: nil,
            readiumLocatorJSON: nil,
            createdAt: Date(timeIntervalSinceReferenceDate: 200)
        )
        let book = try BookEntity(
            id: bookId,
            title: "Book",
            originalFileName: "book.epub",
            readingProgress: 0.2,
            lastLocatorJSON: JSONEncoder().encode(locator),
            contentFingerprint: "new-fingerprint"
        )

        #expect(book.readerLocator == nil)
        #expect(book.readerInitialPosition == nil)
    }
}
