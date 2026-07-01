import Foundation
import SwiftData

@Model
final class ExcerptEntity {
    @Attribute(.unique) var id: UUID
    var bookId: UUID
    var bookTitleSnapshot: String
    var authorDisplaySnapshot: String
    var chapterTitle: String?
    var selectedText: String
    var contextBefore: String
    var contextAfter: String
    var locatorJSON: Data
    var createdAt: Date
    var copiedToClipboard: Bool
    var sourceBookAvailable: Bool
    var sortProgress: Double
    var schemaVersion: Int

    init(
        id: UUID = UUID(),
        bookId: UUID,
        bookTitleSnapshot: String,
        authorDisplaySnapshot: String,
        chapterTitle: String? = nil,
        selectedText: String,
        contextBefore: String = "",
        contextAfter: String = "",
        locatorJSON: Data = Data(),
        createdAt: Date = .now,
        copiedToClipboard: Bool = false,
        sourceBookAvailable: Bool = true,
        sortProgress: Double = 0,
        schemaVersion: Int = 1
    ) {
        self.id = id
        self.bookId = bookId
        self.bookTitleSnapshot = bookTitleSnapshot
        self.authorDisplaySnapshot = authorDisplaySnapshot
        self.chapterTitle = chapterTitle
        self.selectedText = selectedText
        self.contextBefore = contextBefore
        self.contextAfter = contextAfter
        self.locatorJSON = locatorJSON
        self.createdAt = createdAt
        self.copiedToClipboard = copiedToClipboard
        self.sourceBookAvailable = sourceBookAvailable
        self.sortProgress = sortProgress
        self.schemaVersion = schemaVersion
    }
}
