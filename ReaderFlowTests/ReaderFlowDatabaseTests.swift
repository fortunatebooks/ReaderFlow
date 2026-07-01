import Foundation
@testable import ReaderFlow
import SwiftData
import Testing

struct ReaderFlowDatabaseTests {
    @Test func saveReadingProgressUpdatesMatchingBook() async throws {
        let bookId = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let openedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let container = try inMemoryContainer()
        let context = ModelContext(container)
        let book = BookEntity(
            id: bookId,
            title: "Book",
            originalFileName: "book.epub",
            readingProgress: 0.1,
            contentFingerprint: "fingerprint"
        )
        context.insert(book)
        try context.save()

        let database = ReaderFlowDatabase(modelContainer: container)
        try await database.saveReadingProgress(
            ReadingProgressUpdate(
                bookId: bookId,
                bookFingerprint: "fingerprint",
                readingProgress: 0.7,
                locatorJSON: encodedLocator(bookId: bookId, fingerprint: "fingerprint", createdAt: openedAt),
                openedAt: openedAt
            )
        )

        let savedBook = try #require(try fetchBook(bookId: bookId, in: container))
        #expect(savedBook.readingProgress == 0.7)
        #expect(savedBook.lastLocatorJSON == encodedLocator(bookId: bookId, fingerprint: "fingerprint", createdAt: openedAt))
        #expect(savedBook.lastOpenedAt == openedAt)
        #expect(savedBook.lastOpenedSortKey == openedAt)
    }

    @Test func saveReadingProgressIgnoresFingerprintMismatchAndOlderUpdates() async throws {
        let bookId = try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
        let existingOpenedAt = Date(timeIntervalSince1970: 2000)
        let container = try inMemoryContainer()
        let context = ModelContext(container)
        let book = BookEntity(
            id: bookId,
            title: "Book",
            originalFileName: "book.epub",
            lastOpenedAt: existingOpenedAt,
            readingProgress: 0.4,
            lastLocatorJSON: encodedLocator(bookId: bookId, fingerprint: "fingerprint", createdAt: existingOpenedAt),
            contentFingerprint: "fingerprint"
        )
        context.insert(book)
        try context.save()

        let database = ReaderFlowDatabase(modelContainer: container)
        try await database.saveReadingProgress(
            ReadingProgressUpdate(
                bookId: bookId,
                bookFingerprint: "wrong",
                readingProgress: 0.8,
                locatorJSON: encodedLocator(bookId: bookId, fingerprint: "wrong", createdAt: existingOpenedAt.addingTimeInterval(10)),
                openedAt: existingOpenedAt.addingTimeInterval(10)
            )
        )
        try await database.saveReadingProgress(
            ReadingProgressUpdate(
                bookId: bookId,
                bookFingerprint: "fingerprint",
                readingProgress: 0.9,
                locatorJSON: encodedLocator(bookId: bookId, fingerprint: "fingerprint", createdAt: existingOpenedAt.addingTimeInterval(-10)),
                openedAt: existingOpenedAt.addingTimeInterval(-10)
            )
        )

        let savedBook = try #require(try fetchBook(bookId: bookId, in: container))
        #expect(savedBook.readingProgress == 0.4)
        #expect(savedBook.lastLocatorJSON == encodedLocator(bookId: bookId, fingerprint: "fingerprint", createdAt: existingOpenedAt))
        #expect(savedBook.lastOpenedAt == existingOpenedAt)
    }

    @Test func saveReadingProgressAllowsProgressOlderThanLastOpenedButNewerThanPreviousLocator() async throws {
        let bookId = try #require(UUID(uuidString: "33333333-3333-3333-3333-333333333333"))
        let previousProgressAt = Date(timeIntervalSince1970: 2000)
        let reopenedAt = Date(timeIntervalSince1970: 3000)
        let finalProgressAt = Date(timeIntervalSince1970: 2500)
        let container = try inMemoryContainer()
        let context = ModelContext(container)
        let book = BookEntity(
            id: bookId,
            title: "Book",
            originalFileName: "book.epub",
            lastOpenedAt: reopenedAt,
            readingProgress: 0.4,
            lastLocatorJSON: encodedLocator(bookId: bookId, fingerprint: "fingerprint", createdAt: previousProgressAt),
            contentFingerprint: "fingerprint"
        )
        context.insert(book)
        try context.save()

        let database = ReaderFlowDatabase(modelContainer: container)
        try await database.saveReadingProgress(
            ReadingProgressUpdate(
                bookId: bookId,
                bookFingerprint: "fingerprint",
                readingProgress: 0.8,
                locatorJSON: encodedLocator(bookId: bookId, fingerprint: "fingerprint", createdAt: finalProgressAt),
                openedAt: finalProgressAt
            )
        )

        let savedBook = try #require(try fetchBook(bookId: bookId, in: container))
        #expect(savedBook.readingProgress == 0.8)
        #expect(savedBook.lastOpenedAt == reopenedAt)
        #expect(savedBook.lastOpenedSortKey == reopenedAt)
        #expect(savedBook.lastLocatorJSON == encodedLocator(bookId: bookId, fingerprint: "fingerprint", createdAt: finalProgressAt))
    }

    private func inMemoryContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: BookEntity.self,
            ExcerptEntity.self,
            ReaderSettingsEntity.self,
            configurations: configuration
        )
    }

    private func fetchBook(bookId: UUID, in container: ModelContainer) throws -> BookEntity? {
        let context = ModelContext(container)
        var descriptor = FetchDescriptor<BookEntity>(
            predicate: #Predicate<BookEntity> { book in
                book.id == bookId
            }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func encodedLocator(bookId: UUID, fingerprint: String, createdAt: Date) -> Data? {
        let locator = ReaderLocator(
            bookId: bookId,
            bookFingerprint: fingerprint,
            spineIndex: 0,
            href: "chapter.xhtml",
            chapterTitle: "Chapter",
            chapterProgression: 0.5,
            totalProgression: 0.5,
            scrollY: 100,
            documentHeight: 1000,
            textQuote: nil,
            domTextPath: nil,
            contentHash: nil,
            readiumLocatorJSON: nil,
            createdAt: createdAt
        )
        return try? JSONEncoder().encode(locator)
    }
}
