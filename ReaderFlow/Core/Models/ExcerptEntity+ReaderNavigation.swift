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
}
