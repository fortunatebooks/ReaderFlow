import CryptoKit
import Foundation

struct EPUBImportService {
    private let fileStore: AppFileStore
    private let archiveExpander: EPUBArchiveExpander
    private let packageParser: EPUBPackageParser
    private let preflightLimits: EPUBPreflightLimits

    init(
        fileStore: AppFileStore,
        archiveExpander: EPUBArchiveExpander = EPUBArchiveExpander(),
        packageParser: EPUBPackageParser = EPUBPackageParser(),
        preflightLimits: EPUBPreflightLimits = EPUBPreflightLimits()
    ) {
        self.fileStore = fileStore
        self.archiveExpander = archiveExpander
        self.packageParser = packageParser
        self.preflightLimits = preflightLimits
    }

    func importEPUB(from sourceURL: URL, knownFingerprints: Set<String>) async throws -> ImportedEPUBDraft {
        let didStartAccessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let bookId = UUID()
        do {
            let sourceSize = try fileSize(at: sourceURL)
            guard sourceSize <= preflightLimits.maximumCompressedSizeBytes else {
                throw EPUBImportError.tooLarge
            }

            let copiedURL = try fileStore.copyEPUB(from: sourceURL, bookId: bookId)
            let fingerprint = try sha256HexDigest(for: copiedURL)

            guard !knownFingerprints.contains(fingerprint) else {
                throw EPUBImportError.duplicateImport
            }

            let preflight = try await archiveExpander.preflightArchive(at: copiedURL)
            guard preflightLimits.allows(preflight) else {
                throw EPUBImportError.tooLarge
            }

            let expandedURL = try fileStore.expandedDirectory(for: bookId)
            let expandedArchive = try await archiveExpander.expandArchive(at: copiedURL, to: expandedURL)
            let package = try packageParser.parseExpandedEPUB(at: expandedArchive.rootURL)
            guard package.readingOrder.count <= preflightLimits.maximumSpineItemCount else {
                throw EPUBImportError.tooLarge
            }

            return ImportedEPUBDraft(
                id: bookId,
                title: package.metadata.title ?? sourceURL.deletingPathExtension().lastPathComponent,
                authorDisplay: package.metadata.creators.first ?? "Unknown Author",
                authors: package.metadata.creators.map { AuthorPayload(name: $0) },
                languageCode: package.metadata.language,
                coverFileName: coverFileName(in: package),
                originalFileName: sourceURL.lastPathComponent,
                epubFileName: "source.epub",
                expandedDirectoryName: "expanded",
                fileSizeBytes: sourceSize,
                preflight: preflight,
                package: package,
                contentFingerprint: fingerprint
            )
        } catch {
            try? fileStore.removeBookFiles(bookId: bookId)
            throw error
        }
    }

    private func fileSize(at url: URL) throws -> Int64 {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values.fileSize ?? 0)
    }

    private func sha256HexDigest(for url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer {
            try? handle.close()
        }

        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: 1024 * 1024) ?? Data()
            if data.isEmpty {
                break
            }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func coverFileName(in package: EPUBPackageDocument) -> String? {
        guard let coverItem = coverManifestItem(in: package) else {
            return nil
        }
        return package.resourceResolver.normalizedResourcePath(coverItem.href)
    }

    private func coverManifestItem(in package: EPUBPackageDocument) -> EPUBManifestItem? {
        if let coverItemID = package.metadata.coverItemID,
           let coverItem = package.manifestItem(id: coverItemID),
           isImage(coverItem.mediaType)
        {
            return coverItem
        }

        if let coverItem = package.manifest.first(where: { $0.properties.contains("cover-image") && isImage($0.mediaType) }) {
            return coverItem
        }

        return package.manifest.first { item in
            isImage(item.mediaType) && item.id.localizedCaseInsensitiveContains("cover")
        }
    }

    private func isImage(_ mediaType: String) -> Bool {
        let lowercased = mediaType.lowercased()
        return lowercased.hasPrefix("image/") && lowercased != "image/svg+xml"
    }
}

struct ImportedEPUBDraft {
    var id: UUID
    var title: String
    var authorDisplay: String
    var authors: [AuthorPayload]
    var languageCode: String?
    var coverFileName: String?
    var originalFileName: String
    var epubFileName: String
    var expandedDirectoryName: String
    var fileSizeBytes: Int64
    var preflight: EPUBPreflightResult
    var package: EPUBPackageDocument
    var contentFingerprint: String

    func encodedAuthors() -> Data {
        (try? JSONEncoder().encode(authors)) ?? Data()
    }

    func encodedTableOfContents() -> Data {
        let entries = package.readingOrder.map { item in
            TableOfContentsEntry(title: item.href, href: item.href, children: [])
        }
        return (try? JSONEncoder().encode(TableOfContentsPayload(entries: entries))) ?? Data()
    }
}
