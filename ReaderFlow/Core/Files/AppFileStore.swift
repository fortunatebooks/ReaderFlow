import Foundation

struct AppFileStore {
    let rootURL: URL

    init(fileManager: FileManager = .default) throws {
        let supportURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        rootURL = supportURL.appending(path: "ReaderFlow", directoryHint: .isDirectory)
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
}
