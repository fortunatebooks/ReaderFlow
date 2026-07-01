import Foundation

extension BookEntity {
    var readerLocator: ReaderLocator? {
        guard let lastLocatorJSON,
              let locator = try? JSONDecoder().decode(ReaderLocator.self, from: lastLocatorJSON),
              locator.bookId == id,
              locator.bookFingerprint == contentFingerprint
        else {
            return nil
        }
        return locator
    }

    var readerInitialPosition: ReaderInitialPosition? {
        readerLocator.map(ReaderInitialPosition.init(locator:))
    }
}
