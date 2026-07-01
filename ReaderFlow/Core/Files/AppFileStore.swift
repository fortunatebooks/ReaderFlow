import Foundation

enum AppFileStoreError: Error {
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
    }

    var booksURL: URL {
        rootURL.appending(path: "Books", directoryHint: .isDirectory)
    }

    var exportsURL: URL {
        rootURL.appending(path: "Exports", directoryHint: .isDirectory)
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

    func expandedDirectory(for bookId: UUID, fileManager: FileManager = .default) throws -> URL {
        try directory(for: bookId, fileManager: fileManager).appending(path: "expanded", directoryHint: .isDirectory)
    }

    func removeBookFiles(bookId: UUID, fileManager: FileManager = .default) throws {
        let url = booksURL.appending(path: bookId.uuidString, directoryHint: .isDirectory)
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
