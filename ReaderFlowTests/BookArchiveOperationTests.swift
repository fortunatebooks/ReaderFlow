import Foundation
@testable import ReaderFlow
import Testing

struct BookArchiveOperationTests {
    @Test func markArchivedHidesBookAndKeepsRelatedExcerptsInArchive() {
        let bookId = UUID()
        let unrelatedBookId = UUID()
        let archivedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let book = BookEntity(
            id: bookId,
            title: "Book",
            originalFileName: "book.epub",
            contentFingerprint: "fingerprint"
        )
        let relatedExcerpt = ExcerptEntity(
            bookId: bookId,
            bookTitleSnapshot: "Book",
            authorDisplaySnapshot: "Author",
            selectedText: "selected"
        )
        let unrelatedExcerpt = ExcerptEntity(
            bookId: unrelatedBookId,
            bookTitleSnapshot: "Other",
            authorDisplaySnapshot: "Author",
            selectedText: "other"
        )

        BookArchiveOperation(archivedAt: archivedAt).markArchived(
            book: book,
            excerpts: [relatedExcerpt, unrelatedExcerpt]
        )

        #expect(book.isArchived)
        #expect(book.archivedAt == archivedAt)
        #expect(book.deletedFileAt == nil)
        #expect(book.importStatus == BookImportStatus.archived.rawValue)
        #expect(!relatedExcerpt.sourceBookAvailable)
        #expect(unrelatedExcerpt.sourceBookAvailable)
    }

    @Test func markFilesDeletedRecordsDeletionTimestamp() {
        let archivedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let book = BookEntity(
            title: "Book",
            originalFileName: "book.epub",
            contentFingerprint: "fingerprint"
        )

        BookArchiveOperation(archivedAt: archivedAt).markFilesDeleted(book: book)

        #expect(book.deletedFileAt == archivedAt)
        #expect(book.importStatus == BookImportStatus.archived.rawValue)
    }

    @Test func snapshotRestoresPreArchiveStateAfterFailedMetadataSave() {
        let archivedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let originalArchivedAt = Date(timeIntervalSince1970: 1_600_000_000)
        let originalDeletedAt = Date(timeIntervalSince1970: 1_600_000_100)
        let book = BookEntity(
            title: "Book",
            originalFileName: "book.epub",
            archivedAt: originalArchivedAt,
            deletedFileAt: originalDeletedAt,
            importStatus: BookImportStatus.failed.rawValue,
            contentFingerprint: "fingerprint"
        )
        let excerpt = ExcerptEntity(
            bookId: book.id,
            bookTitleSnapshot: "Book",
            authorDisplaySnapshot: "Author",
            selectedText: "selected",
            sourceBookAvailable: true
        )
        let snapshot = BookArchiveSnapshot(book: book, excerpts: [excerpt])

        BookArchiveOperation(archivedAt: archivedAt).markArchived(book: book, excerpts: [excerpt])
        snapshot.restore()

        #expect(!book.isArchived)
        #expect(book.archivedAt == originalArchivedAt)
        #expect(book.deletedFileAt == originalDeletedAt)
        #expect(book.importStatus == BookImportStatus.failed.rawValue)
        #expect(excerpt.sourceBookAvailable)
    }
}
