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

        let text = ExcerptTextExporter().exportLibrary(excerpts: [laterBookExcerpt, earlierBookExcerpt])

        #expect(text.contains("ReaderFlow Library Excerpts"))
        #expect(text.contains("Book Count: 2"))
        #expect(text.contains("Excerpt Count: 2"))
        let aBookIndex = try #require(text.range(of: "Book: A Book")?.lowerBound)
        let zBookIndex = try #require(text.range(of: "Book: Z Book")?.lowerBound)
        #expect(aBookIndex < zBookIndex)
    }
}
