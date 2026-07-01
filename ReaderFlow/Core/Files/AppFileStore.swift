import Foundation

enum AppFileStoreError: Error {
    case bookDirectoryAlreadyExists
    case missingStagedImport
    case unsafeExportFileName
}

struct AppFileStore {
    let rootURL: URL

    init(fileManager: FileManager = .default) throws {
        let supportURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        try self.init(rootURL: supportURL.appending(path: "ReaderFlow", directoryHint: .isDirectory), fileManager: fileManager)
    }

    init(rootURL: URL, fileManager: FileManager = .default) throws {
        self.rootURL = rootURL
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: booksURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: exportsURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: stagingURL, withIntermediateDirectories: true)
    }

    var booksURL: URL {
        rootURL.appending(path: "Books", directoryHint: .isDirectory)
    }

    var exportsURL: URL {
        rootURL.appending(path: "Exports", directoryHint: .isDirectory)
    }

    var stagingURL: URL {
        rootURL.appending(path: "Staging", directoryHint: .isDirectory)
    }

    func directory(for bookId: UUID, fileManager: FileManager = .default) throws -> URL {
        let url = booksURL.appending(path: bookId.uuidString, directoryHint: .isDirectory)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func copyEPUB(from sourceURL: URL, bookId: UUID, fileManager: FileManager = .default) throws -> URL {
        let destination = try directory(for: bookId, fileManager: fileManager).appending(path: "source.epub")
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: sourceURL, to: destination)
        return destination
    }

    func stagingDirectory(for importId: UUID, fileManager: FileManager = .default) throws -> URL {
        let url = stagingURL.appending(path: importId.uuidString, directoryHint: .isDirectory)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func copyEPUBToStaging(from sourceURL: URL, importId: UUID, fileManager: FileManager = .default) throws -> URL {
        let destination = try stagingDirectory(for: importId, fileManager: fileManager).appending(path: "source.epub")
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: sourceURL, to: destination)
        return destination
    }

    func stagedExpandedDirectory(for importId: UUID, fileManager: FileManager = .default) throws -> URL {
        try stagingDirectory(for: importId, fileManager: fileManager).appending(path: "expanded", directoryHint: .isDirectory)
    }

    func promoteStagedBook(importId: UUID, bookId: UUID, fileManager: FileManager = .default) throws -> URL {
        let stagedDirectory = stagingURL.appending(path: importId.uuidString, directoryHint: .isDirectory)
        guard fileManager.fileExists(atPath: stagedDirectory.path) else {
            throw AppFileStoreError.missingStagedImport
        }
        let destination = booksURL.appending(path: bookId.uuidString, directoryHint: .isDirectory)
        guard !fileManager.fileExists(atPath: destination.path) else {
            throw AppFileStoreError.bookDirectoryAlreadyExists
        }
        try fileManager.moveItem(at: stagedDirectory, to: destination)
        return destination
    }

    func expandedDirectory(for bookId: UUID, fileManager: FileManager = .default) throws -> URL {
        try directory(for: bookId, fileManager: fileManager).appending(path: "expanded", directoryHint: .isDirectory)
    }

    func removeBookFiles(bookId: UUID, fileManager: FileManager = .default) throws {
        let url = booksURL.appending(path: bookId.uuidString, directoryHint: .isDirectory)
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    func removeStagedImport(importId: UUID, fileManager: FileManager = .default) throws {
        let url = stagingURL.appending(path: importId.uuidString, directoryHint: .isDirectory)
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    func writeExportFile(named fileName: String, contents: String, fileManager: FileManager = .default) throws -> URL {
        guard isSafeExportFileName(fileName) else {
            throw AppFileStoreError.unsafeExportFileName
        }
        let destination = exportsURL.appending(path: fileName, directoryHint: .notDirectory)
        try fileManager.createDirectory(at: exportsURL, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try contents.write(to: destination, atomically: true, encoding: .utf8)
        return destination
    }

    func removeExportFiles(olderThan cutoffDate: Date, fileManager: FileManager = .default) throws {
        guard fileManager.fileExists(atPath: exportsURL.path) else {
            return
        }
        let exportFiles = try fileManager.contentsOfDirectory(
            at: exportsURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        for fileURL in exportFiles {
            let values = try fileURL.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
            guard values.isRegularFile == true else {
                continue
            }
            let modifiedAt = values.contentModificationDate ?? .distantPast
            if modifiedAt < cutoffDate {
                try fileManager.removeItem(at: fileURL)
            }
        }
    }

    private func isSafeExportFileName(_ fileName: String) -> Bool {
        let trimmed = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty
            && trimmed != "."
            && trimmed != ".."
            && !fileName.contains("/")
            && !fileName.contains("\\")
            && !fileName.contains("\u{0}")
    }
}
