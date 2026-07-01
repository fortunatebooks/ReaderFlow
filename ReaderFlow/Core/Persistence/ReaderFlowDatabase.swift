import Foundation
import SwiftData

@ModelActor
actor ReaderFlowDatabase {
    func save() throws {
        try modelContext.save()
    }

    func saveReadingProgress(_ update: ReadingProgressUpdate) throws {
        let bookId = update.bookId
        let fingerprint = update.bookFingerprint
        var descriptor = FetchDescriptor<BookEntity>(
            predicate: #Predicate<BookEntity> { book in
                book.id == bookId && book.contentFingerprint == fingerprint
            }
        )
        descriptor.fetchLimit = 1

        guard let book = try modelContext.fetch(descriptor).first,
              !book.isArchived
        else {
            return
        }

        if let lastProgressSavedAt = book.lastProgressSavedAt,
           lastProgressSavedAt > update.openedAt
        {
            return
        }

        book.readingProgress = update.readingProgress
        book.lastLocatorJSON = update.locatorJSON
        let openedAt = max(book.lastOpenedAt ?? update.openedAt, update.openedAt)
        book.lastOpenedAt = openedAt
        book.lastOpenedSortKey = openedAt
        try modelContext.save()
    }
}

private extension BookEntity {
    var lastProgressSavedAt: Date? {
        guard let lastLocatorJSON,
              let locator = try? JSONDecoder().decode(ReaderLocator.self, from: lastLocatorJSON)
        else {
            return nil
        }
        return locator.createdAt
    }
}
