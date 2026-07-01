import Foundation

extension ExcerptEntity {
    var readerLocator: ReaderLocator? {
        guard !locatorJSON.isEmpty else {
            return nil
        }
        return try? JSONDecoder().decode(ReaderLocator.self, from: locatorJSON)
    }

    var readerJumpProgress: Double {
        readerInitialPosition.progress
    }

    var readerInitialPosition: ReaderInitialPosition {
        if let readerLocator {
            return ReaderInitialPosition(locator: readerLocator)
        }
        return ReaderInitialPosition(progress: sortProgress)
    }

    func readerHighlightPayload(expectedBookId: UUID, expectedBookFingerprint: String) -> ReaderHighlightPayload? {
        guard let locator = readerLocator,
              locator.bookId == expectedBookId,
              locator.bookFingerprint == expectedBookFingerprint,
              !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }
        return ReaderHighlightPayload(
            id: id,
            selectedText: selectedText,
            contextBefore: contextBefore,
            contextAfter: contextAfter,
            locator: locator
        )
    }
}
