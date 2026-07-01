import Foundation

struct BookArchiveOperation {
    var archivedAt: Date

    func markArchived(book: BookEntity, excerpts: [ExcerptEntity], filesDeleted: Bool = false) {
        book.isArchived = true
        book.archivedAt = archivedAt
        book.deletedFileAt = filesDeleted ? archivedAt : nil
        book.importStatus = BookImportStatus.archived.rawValue

        for excerpt in excerpts where excerpt.bookId == book.id {
            excerpt.sourceBookAvailable = false
        }
    }

    func markFilesDeleted(book: BookEntity) {
        book.deletedFileAt = archivedAt
        book.importStatus = BookImportStatus.archived.rawValue
    }
}

struct BookArchiveSnapshot {
    private let book: BookEntity
    private let isArchived: Bool
    private let archivedAt: Date?
    private let deletedFileAt: Date?
    private let importStatus: String
    private let excerptAvailability: [(excerpt: ExcerptEntity, sourceBookAvailable: Bool)]

    init(book: BookEntity, excerpts: [ExcerptEntity]) {
        self.book = book
        isArchived = book.isArchived
        archivedAt = book.archivedAt
        deletedFileAt = book.deletedFileAt
        importStatus = book.importStatus
        excerptAvailability = excerpts.map { ($0, $0.sourceBookAvailable) }
    }

    func restore() {
        book.isArchived = isArchived
        book.archivedAt = archivedAt
        book.deletedFileAt = deletedFileAt
        book.importStatus = importStatus
        for item in excerptAvailability {
            item.excerpt.sourceBookAvailable = item.sourceBookAvailable
        }
    }
}
