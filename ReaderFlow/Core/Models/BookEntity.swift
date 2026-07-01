import Foundation
import SwiftData

@Model
final class BookEntity {
    @Attribute(.unique) var id: UUID
    var title: String
    var authorDisplay: String
    var authorsJSON: Data
    var languageCode: String?
    var titleSortKey: String
    var authorSortKey: String
    var originalFileName: String
    var epubFileName: String?
    var expandedDirectoryName: String?
    var coverFileName: String?
    var importedAt: Date
    var lastOpenedAt: Date?
    var lastOpenedSortKey: Date?
    var readingProgress: Double
    var lastLocatorJSON: Data?
    var tableOfContentsJSON: Data?
    var isArchived: Bool
    var archivedAt: Date?
    var deletedFileAt: Date?
    var importStatus: String
    var fileSizeBytes: Int64
    var expandedSizeBytes: Int64
    var xhtmlSizeBytes: Int64
    var spineItemCount: Int
    var estimatedDomNodeCount: Int
    var imageCount: Int
    @Attribute(.unique) var contentFingerprint: String
    var schemaVersion: Int

    init(
        id: UUID = UUID(),
        title: String,
        authorDisplay: String = "Unknown Author",
        authorsJSON: Data = Data(),
        languageCode: String? = nil,
        originalFileName: String,
        epubFileName: String? = nil,
        expandedDirectoryName: String? = nil,
        coverFileName: String? = nil,
        importedAt: Date = .now,
        lastOpenedAt: Date? = nil,
        readingProgress: Double = 0,
        lastLocatorJSON: Data? = nil,
        tableOfContentsJSON: Data? = nil,
        isArchived: Bool = false,
        archivedAt: Date? = nil,
        deletedFileAt: Date? = nil,
        importStatus: String = BookImportStatus.imported.rawValue,
        fileSizeBytes: Int64 = 0,
        expandedSizeBytes: Int64 = 0,
        xhtmlSizeBytes: Int64 = 0,
        spineItemCount: Int = 0,
        estimatedDomNodeCount: Int = 0,
        imageCount: Int = 0,
        contentFingerprint: String,
        schemaVersion: Int = 1
    ) {
        self.id = id
        self.title = title
        self.authorDisplay = authorDisplay
        self.authorsJSON = authorsJSON
        self.languageCode = languageCode
        titleSortKey = title.normalizedSortKey
        authorSortKey = authorDisplay.normalizedSortKey
        self.originalFileName = originalFileName
        self.epubFileName = epubFileName
        self.expandedDirectoryName = expandedDirectoryName
        self.coverFileName = coverFileName
        self.importedAt = importedAt
        self.lastOpenedAt = lastOpenedAt
        lastOpenedSortKey = lastOpenedAt
        self.readingProgress = readingProgress
        self.lastLocatorJSON = lastLocatorJSON
        self.tableOfContentsJSON = tableOfContentsJSON
        self.isArchived = isArchived
        self.archivedAt = archivedAt
        self.deletedFileAt = deletedFileAt
        self.importStatus = importStatus
        self.fileSizeBytes = fileSizeBytes
        self.expandedSizeBytes = expandedSizeBytes
        self.xhtmlSizeBytes = xhtmlSizeBytes
        self.spineItemCount = spineItemCount
        self.estimatedDomNodeCount = estimatedDomNodeCount
        self.imageCount = imageCount
        self.contentFingerprint = contentFingerprint
        self.schemaVersion = schemaVersion
    }
}

enum BookImportStatus: String, Codable, CaseIterable {
    case imported
    case failed
    case archived
}

private extension String {
    var normalizedSortKey: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
