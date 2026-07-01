import Foundation
@testable import ReaderFlow
import Testing

struct ExcerptTextExporterTests {
    @Test func exportsPlainTextWithContext() {
        let excerpt = ExcerptEntity(
            bookId: UUID(),
            bookTitleSnapshot: "Book",
            authorDisplaySnapshot: "Author",
            chapterTitle: "Chapter 1",
            selectedText: "selected words",
            contextBefore: "before",
            contextAfter: "after",
            sortProgress: 0.42
        )

        let text = ExcerptTextExporter().export(bookTitle: "Book", author: "Author", excerpts: [excerpt])

        #expect(text.contains("ReaderFlow Excerpts"))
        #expect(text.contains("Chapter: Chapter 1"))
        #expect(text.contains("selected words"))
        #expect(text.contains("Context: ...before [excerpt] selected words [/excerpt] after..."))
    }

    @Test func exportsSingleExcerptAndPlainTextFilenames() {
        let excerpt = ExcerptEntity(
            bookId: UUID(),
            bookTitleSnapshot: "Book / Draft: One",
            authorDisplaySnapshot: "Author",
            chapterTitle: "Chapter 1",
            selectedText: "selected words",
            contextBefore: "before",
            contextAfter: "after",
            sortProgress: 0.42
        )
        let exporter = ExcerptTextExporter()

        let text = exporter.export(excerpt: excerpt)

        #expect(text.contains("ReaderFlow Excerpts"))
        #expect(text.contains("Book: Book / Draft: One"))
        #expect(text.contains("Excerpt Count: 1"))
        #expect(exporter.bookExportFilename(bookTitle: "Book / Draft: One") == "ReaderFlow - Book Draft One - Excerpts.txt")
        #expect(exporter.singleExcerptExportFilename(bookTitle: "Book / Draft: One") == "ReaderFlow - Book Draft One - Excerpt.txt")
        #expect(exporter.libraryExportFilename() == "ReaderFlow - All Excerpts.txt")
    }

    @Test func buildsTransferableExportFiles() {
        let excerpt = ExcerptEntity(
            bookId: UUID(),
            bookTitleSnapshot: "Book",
            authorDisplaySnapshot: "Author",
            chapterTitle: "Chapter 1",
            selectedText: "selected words",
            sortProgress: 0.42
        )

        let bookFile = ExcerptTextExportFile.book(bookTitle: "Book", author: "Author", excerpts: [excerpt])
        let libraryFile = ExcerptTextExportFile.library(excerpts: [excerpt])
        let singleFile = ExcerptTextExportFile.singleExcerpt(excerpt)

        #expect(bookFile.filename == "ReaderFlow - Book - Excerpts.txt")
        #expect(bookFile.text.contains("Book: Book"))
        #expect(libraryFile.filename == "ReaderFlow - All Excerpts.txt")
        #expect(libraryFile.text.contains("ReaderFlow Library Excerpts"))
        #expect(singleFile.filename == "ReaderFlow - Book - Excerpt.txt")
        #expect(singleFile.text.contains("Excerpt Count: 1"))
    }

    @Test func writesExportTextFile() throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory
            .appending(path: "ReaderFlowTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer {
            try? fileManager.removeItem(at: rootURL)
        }
        let store = try AppFileStore(rootURL: rootURL, fileManager: fileManager)

        let fileURL = try store.writeExportFile(named: "ReaderFlow - Book - Excerpts.txt", contents: "export text", fileManager: fileManager)

        #expect(fileURL.lastPathComponent == "ReaderFlow - Book - Excerpts.txt")
        #expect(try String(contentsOf: fileURL, encoding: .utf8) == "export text")

        for unsafeName in ["", " ", ".", "..", "../escape.txt", #"bad\name.txt"#, "bad\u{0}name.txt"] {
            do {
                _ = try store.writeExportFile(named: unsafeName, contents: "bad", fileManager: fileManager)
                Issue.record("Expected unsafe export filename to be rejected: \(unsafeName)")
            } catch AppFileStoreError.unsafeExportFileName {
            } catch {
                Issue.record("Expected AppFileStoreError.unsafeExportFileName for \(unsafeName), got \(error).")
            }
        }
    }

    @Test func exportsLibraryExcerptsGroupedByBook() throws {
        let laterBookExcerpt = ExcerptEntity(
            bookId: UUID(),
            bookTitleSnapshot: "Z Book",
            authorDisplaySnapshot: "Author Z",
            chapterTitle: "Chapter Z",
            selectedText: "z words",
            sortProgress: 0.2
        )
        let earlierBookExcerpt = ExcerptEntity(
            bookId: UUID(),
            bookTitleSnapshot: "A Book",
            authorDisplaySnapshot: "Author A",
            chapterTitle: "Chapter A",
            selectedText: "a words",
            sortProgress: 0.1
        )
        let sameTitleDifferentBookExcerpt = ExcerptEntity(
            bookId: UUID(),
            bookTitleSnapshot: "A Book",
            authorDisplaySnapshot: "Author B",
            chapterTitle: "Chapter B",
            selectedText: "b words",
            sortProgress: 0.3
        )

        let text = ExcerptTextExporter().exportLibrary(excerpts: [laterBookExcerpt, earlierBookExcerpt, sameTitleDifferentBookExcerpt])

        #expect(text.contains("ReaderFlow Library Excerpts"))
        #expect(text.contains("Book Count: 3"))
        #expect(text.contains("Excerpt Count: 3"))
        let aBookIndex = try #require(text.range(of: "Book: A Book")?.lowerBound)
        let authorBIndex = try #require(text.range(of: "Author: Author B")?.lowerBound)
        let zBookIndex = try #require(text.range(of: "Book: Z Book")?.lowerBound)
        #expect(aBookIndex < zBookIndex)
        #expect(authorBIndex < zBookIndex)
        #expect(text.components(separatedBy: "Book: A Book").count - 1 == 2)
    }
}
