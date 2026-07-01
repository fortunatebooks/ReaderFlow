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
