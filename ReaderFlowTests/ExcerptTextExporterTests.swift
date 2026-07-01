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
}
