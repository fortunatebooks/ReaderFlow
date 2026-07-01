import Foundation

struct ExcerptTextExporter {
    func export(bookTitle: String, author: String, excerpts: [ExcerptEntity], exportedAt: Date = .now) -> String {
        var output = """
        ReaderFlow Excerpts
        Book: \(bookTitle)
        Author: \(author)
        Exported: \(exportedAt.formatted(date: .abbreviated, time: .shortened))
        Excerpt Count: \(excerpts.count)

        ---

        """

        for excerpt in excerpts.sorted(by: { $0.sortProgress < $1.sortProgress }) {
            output += """
            Chapter: \(excerpt.chapterTitle ?? "Unknown")
            Location: \(Int(excerpt.sortProgress * 100))%
            Saved: \(excerpt.createdAt.formatted(date: .abbreviated, time: .shortened))

            \(excerpt.selectedText)

            """
            if !excerpt.contextBefore.isEmpty || !excerpt.contextAfter.isEmpty {
                output += "Context: ...\(excerpt.contextBefore) [excerpt] \(excerpt.selectedText) [/excerpt] \(excerpt.contextAfter)...\n\n"
            }
            output += "---\n\n"
        }

        return output
    }
}
