import Foundation
import SwiftData

struct ReadingProgressStore {
    private let database: ReaderFlowDatabase

    init(modelContainer: ModelContainer) {
        database = ReaderFlowDatabase(modelContainer: modelContainer)
    }

    func save(_ update: ReadingProgressUpdate) async throws {
        try await database.saveReadingProgress(update)
    }
}

struct ReadingProgressUpdate: Hashable {
    var bookId: UUID
    var bookFingerprint: String
    var readingProgress: Double
    var locatorJSON: Data?
    var openedAt: Date

    init(
        bookId: UUID,
        bookFingerprint: String,
        readingProgress: Double,
        locatorJSON: Data?,
        openedAt: Date = .now
    ) {
        self.bookId = bookId
        self.bookFingerprint = bookFingerprint
        self.readingProgress = Self.bounded(readingProgress)
        self.locatorJSON = locatorJSON
        self.openedAt = openedAt
    }

    private static func bounded(_ value: Double) -> Double {
        guard value.isFinite else {
            return 0
        }
        return min(1, max(0, value))
    }
}
