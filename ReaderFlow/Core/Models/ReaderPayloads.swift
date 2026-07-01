import Foundation

struct AuthorPayload: Codable, Hashable {
    var name: String
}

struct TableOfContentsPayload: Codable, Hashable {
    var entries: [TableOfContentsEntry]
}

struct TableOfContentsEntry: Codable, Hashable, Identifiable {
    var id: String {
        href + title
    }

    var title: String
    var href: String
    var children: [TableOfContentsEntry]
}

struct ReaderLocator: Codable, Hashable {
    var bookId: UUID
    var bookFingerprint: String
    var spineIndex: Int
    var href: String
    var chapterTitle: String?
    var chapterProgression: Double
    var totalProgression: Double
    var scrollY: Double
    var documentHeight: Double
    var textQuote: TextQuoteSelector?
    var domTextPath: String?
    var contentHash: String?
    var readiumLocatorJSON: Data?
    var createdAt: Date
}

struct ReaderInitialPosition: Hashable {
    var progress: Double
    var href: String?
    var chapterProgression: Double?
    var scrollY: Double?
    var documentHeight: Double?

    init(
        progress: Double,
        href: String? = nil,
        chapterProgression: Double? = nil,
        scrollY: Double? = nil,
        documentHeight: Double? = nil
    ) {
        self.progress = ReaderInitialPosition.bounded(progress)
        self.href = href
        self.chapterProgression = chapterProgression.map(ReaderInitialPosition.bounded)
        self.scrollY = scrollY.map { max(0, $0) }
        self.documentHeight = documentHeight.map { max(1, $0) }
    }

    init(locator: ReaderLocator) {
        self.init(
            progress: locator.totalProgression,
            href: locator.href.isEmpty ? nil : locator.href,
            chapterProgression: locator.chapterProgression,
            scrollY: locator.scrollY,
            documentHeight: locator.documentHeight
        )
    }

    private static func bounded(_ value: Double) -> Double {
        min(1, max(0, value))
    }
}

struct TextQuoteSelector: Codable, Hashable {
    var exact: String
    var prefix: String
    var suffix: String
    var normalizedStartOffset: Int?
    var normalizedEndOffset: Int?
}

struct ReaderSelectionPayload: Codable, Hashable {
    var highlightId: UUID
    var selectedText: String
    var contextBefore: String
    var contextAfter: String
    var locator: ReaderLocator
}

struct ReaderHighlightPayload: Codable, Hashable, Identifiable {
    var id: UUID
    var selectedText: String
    var contextBefore: String
    var contextAfter: String
    var locator: ReaderLocator
}
