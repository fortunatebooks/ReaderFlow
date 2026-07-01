import Foundation
import ReadiumZIPFoundation

struct EPUBArchiveExpander {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func expandArchive(at sourceURL: URL, to destinationURL: URL) async throws -> ExpandedEPUBArchive {
        try await validateArchiveEntries(at: sourceURL)

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)

        try await fileManager.unzipItem(
            at: sourceURL.absoluteURL,
            to: destinationURL.absoluteURL,
            skipCRC32: true,
            allowUncontainedSymlinks: false
        )
        try removeIgnoredMetadata(from: destinationURL)

        return ExpandedEPUBArchive(rootURL: destinationURL)
    }

    func preflightArchive(at sourceURL: URL) async throws -> EPUBPreflightResult {
        let archive = try await Archive(url: sourceURL.absoluteURL, accessMode: .read)
        var expandedSizeBytes: Int64 = 0
        var xhtmlSizeBytes: Int64 = 0
        var xhtmlEntryCount = 0
        var imageCount = 0
        var estimatedDomNodeCount = 0

        for entry in try await archive.entries() {
            guard Self.isSafeArchivePath(entry.path) else {
                throw EPUBArchiveExpansionError.unsafeEntryPath(entry.path)
            }

            let path = entry.path.lowercased()
            let uncompressedSize = Int64(clamping: entry.uncompressedSize)
            expandedSizeBytes = saturatingAdd(expandedSizeBytes, max(0, uncompressedSize))

            if path.hasSuffix(".xhtml") || path.hasSuffix(".html") || path.hasSuffix(".htm") {
                xhtmlSizeBytes = saturatingAdd(xhtmlSizeBytes, max(0, uncompressedSize))
                xhtmlEntryCount += 1
                estimatedDomNodeCount = estimatedDomNodeCount.saturatingAdd(max(1, Int(clamping: uncompressedSize / 80)))
            }

            if path.hasSuffix(".jpg") || path.hasSuffix(".jpeg") || path.hasSuffix(".png") ||
                path.hasSuffix(".gif") || path.hasSuffix(".webp") || path.hasSuffix(".svg")
            {
                imageCount += 1
            }
        }

        let compressedSize = (try? sourceURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        return EPUBPreflightResult(
            compressedSizeBytes: compressedSize,
            expandedSizeBytes: expandedSizeBytes,
            xhtmlSizeBytes: xhtmlSizeBytes,
            spineItemCount: xhtmlEntryCount,
            estimatedDomNodeCount: estimatedDomNodeCount,
            imageCount: imageCount
        )
    }

    func validateArchiveEntries(at sourceURL: URL) async throws {
        let archive = try await Archive(url: sourceURL.absoluteURL, accessMode: .read)
        for entry in try await archive.entries() {
            guard Self.isSafeArchivePath(entry.path) else {
                throw EPUBArchiveExpansionError.unsafeEntryPath(entry.path)
            }
        }
    }

    static func isSafeArchivePath(_ path: String) -> Bool {
        guard !path.isEmpty,
              let decoded = path.removingPercentEncoding,
              !decoded.hasPrefix("/")
        else {
            return false
        }

        let components = decoded.split(separator: "/", omittingEmptySubsequences: false)
        return !components.contains { component in
            component == ".." || component == "."
        }
    }

    private func removeIgnoredMetadata(from rootURL: URL) throws {
        let macOSMetadata = rootURL.appending(path: "__MACOSX", directoryHint: .isDirectory)
        if fileManager.fileExists(atPath: macOSMetadata.path) {
            try fileManager.removeItem(at: macOSMetadata)
        }

        let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: []
        )
        while let url = enumerator?.nextObject() as? URL {
            if url.lastPathComponent == ".DS_Store" {
                try? fileManager.removeItem(at: url)
            }
        }
    }

    private func saturatingAdd(_ lhs: Int64, _ rhs: Int64) -> Int64 {
        let result = lhs.addingReportingOverflow(rhs)
        return result.overflow ? Int64.max : result.partialValue
    }
}

private extension Int {
    func saturatingAdd(_ rhs: Int) -> Int {
        let result = addingReportingOverflow(rhs)
        return result.overflow ? Int.max : result.partialValue
    }
}

struct ExpandedEPUBArchive: Hashable {
    var rootURL: URL

    var containerURL: URL {
        rootURL
            .appending(path: "META-INF", directoryHint: .isDirectory)
            .appending(path: "container.xml")
    }
}

enum EPUBArchiveExpansionError: LocalizedError, Equatable {
    case unsafeEntryPath(String)

    var errorDescription: String? {
        switch self {
        case let .unsafeEntryPath(path):
            "EPUB archive contains an unsafe path: \(path)"
        }
    }
}
