import Foundation
@testable import ReaderFlow
import Testing

struct AppFileStoreTests {
    @Test func promotesStagedBookIntoPermanentBookDirectory() throws {
        let fileManager = FileManager.default
        let rootURL = temporaryRootURL()
        defer {
            try? fileManager.removeItem(at: rootURL)
        }
        let store = try AppFileStore(rootURL: rootURL, fileManager: fileManager)
        let importId = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let bookId = try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
        let sourceURL = rootURL.appending(path: "incoming.epub")
        try Data("epub".utf8).write(to: sourceURL)

        let stagedSourceURL = try store.copyEPUBToStaging(from: sourceURL, importId: importId, fileManager: fileManager)
        let stagedExpandedURL = try store.stagedExpandedDirectory(for: importId, fileManager: fileManager)
        try fileManager.createDirectory(at: stagedExpandedURL, withIntermediateDirectories: true)
        try Data("chapter".utf8).write(to: stagedExpandedURL.appending(path: "chapter.xhtml"))

        let promotedURL = try store.promoteStagedBook(importId: importId, bookId: bookId, fileManager: fileManager)

        #expect(stagedSourceURL.lastPathComponent == "source.epub")
        #expect(!fileManager.fileExists(atPath: store.stagingURL.appending(path: importId.uuidString).path))
        #expect(fileManager.fileExists(atPath: promotedURL.appending(path: "source.epub").path))
        #expect(fileManager.fileExists(atPath: promotedURL.appending(path: "expanded").appending(path: "chapter.xhtml").path))
    }

    @Test func removesStagedImportWithoutTouchingPermanentBooks() throws {
        let fileManager = FileManager.default
        let rootURL = temporaryRootURL()
        defer {
            try? fileManager.removeItem(at: rootURL)
        }
        let store = try AppFileStore(rootURL: rootURL, fileManager: fileManager)
        let importId = try #require(UUID(uuidString: "33333333-3333-3333-3333-333333333333"))
        let bookId = try #require(UUID(uuidString: "44444444-4444-4444-4444-444444444444"))
        _ = try store.stagingDirectory(for: importId, fileManager: fileManager)
        _ = try store.directory(for: bookId, fileManager: fileManager)

        try store.removeStagedImport(importId: importId, fileManager: fileManager)

        #expect(!fileManager.fileExists(atPath: store.stagingURL.appending(path: importId.uuidString).path))
        #expect(fileManager.fileExists(atPath: store.booksURL.appending(path: bookId.uuidString).path))
    }

    @Test func promotionRefusesToOverwriteExistingBookDirectory() throws {
        let fileManager = FileManager.default
        let rootURL = temporaryRootURL()
        defer {
            try? fileManager.removeItem(at: rootURL)
        }
        let store = try AppFileStore(rootURL: rootURL, fileManager: fileManager)
        let importId = try #require(UUID(uuidString: "55555555-5555-5555-5555-555555555555"))
        let bookId = try #require(UUID(uuidString: "66666666-6666-6666-6666-666666666666"))
        let existingBookURL = try store.directory(for: bookId, fileManager: fileManager)
        try Data("existing".utf8).write(to: existingBookURL.appending(path: "source.epub"))
        _ = try store.stagingDirectory(for: importId, fileManager: fileManager)

        do {
            _ = try store.promoteStagedBook(importId: importId, bookId: bookId, fileManager: fileManager)
            Issue.record("Expected promotion to refuse an existing book directory.")
        } catch AppFileStoreError.bookDirectoryAlreadyExists {
            #expect(fileManager.fileExists(atPath: existingBookURL.appending(path: "source.epub").path))
            #expect(fileManager.fileExists(atPath: store.stagingURL.appending(path: importId.uuidString).path))
        }
    }

    private func temporaryRootURL() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "ReaderFlowTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }
}
