import Foundation
@testable import ReaderFlow
import Testing

struct ReadingProgressStoreTests {
    @Test func readingProgressUpdateBoundsStoredProgress() {
        let bookId = UUID()

        #expect(
            ReadingProgressUpdate(
                bookId: bookId,
                bookFingerprint: "fingerprint",
                readingProgress: -0.3,
                locatorJSON: nil
            ).readingProgress == 0
        )
        #expect(
            ReadingProgressUpdate(
                bookId: bookId,
                bookFingerprint: "fingerprint",
                readingProgress: 1.4,
                locatorJSON: nil
            ).readingProgress == 1
        )
        #expect(
            ReadingProgressUpdate(
                bookId: bookId,
                bookFingerprint: "fingerprint",
                readingProgress: .nan,
                locatorJSON: nil
            ).readingProgress == 0
        )
    }

    @Test func readingProgressUpdateKeepsPrimitivePersistenceFields() throws {
        let bookId = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let openedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let locatorJSON = Data(#"{"href":"chapter.xhtml"}"#.utf8)

        let update = ReadingProgressUpdate(
            bookId: bookId,
            bookFingerprint: "fingerprint",
            readingProgress: 0.42,
            locatorJSON: locatorJSON,
            openedAt: openedAt
        )

        #expect(update.bookId == bookId)
        #expect(update.bookFingerprint == "fingerprint")
        #expect(update.readingProgress == 0.42)
        #expect(update.locatorJSON == locatorJSON)
        #expect(update.openedAt == openedAt)
    }
}
