import Foundation

struct ExcerptTextExporter {
    func bookExportFilename(bookTitle: String) -> String {
        "ReaderFlow - \(sanitizedFilenameComponent(bookTitle, fallback: "Untitled Book")) - Excerpts.txt"
    }

    func libraryExportFilename() -> String {
        "ReaderFlow - All Excerpts.txt"
    }

    func singleExcerptExportFilename(bookTitle: String) -> String {
        "ReaderFlow - \(sanitizedFilenameComponent(bookTitle, fallback: "Untitled Book")) - Excerpt.txt"
    }

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

    func export(excerpt: ExcerptEntity, exportedAt: Date = .now) -> String {
        export(
            bookTitle: excerpt.bookTitleSnapshot,
            author: excerpt.authorDisplaySnapshot,
            excerpts: [excerpt],
            exportedAt: exportedAt
        )
    }

    func exportLibrary(excerpts: [ExcerptEntity], exportedAt: Date = .now) -> String {
        let groupedExcerpts = Dictionary(grouping: excerpts, by: ExcerptExportBookKey.init)
            .map { key, excerpts in
                (
                    key: key,
                    title: key.title,
                    author: key.author,
                    excerpts: excerpts.sorted { $0.sortProgress < $1.sortProgress }
                )
            }
            .sorted { lhs, rhs in
                let titleComparison = lhs.title.localizedStandardCompare(rhs.title)
                if titleComparison != .orderedSame {
                    return titleComparison == .orderedAscending
                }
                let authorComparison = lhs.author.localizedStandardCompare(rhs.author)
                if authorComparison != .orderedSame {
                    return authorComparison == .orderedAscending
                }
                return lhs.key.bookId.uuidString < rhs.key.bookId.uuidString
            }

        var output = """
        ReaderFlow Library Excerpts
        Exported: \(exportedAt.formatted(date: .abbreviated, time: .shortened))
        Book Count: \(groupedExcerpts.count)
        Excerpt Count: \(excerpts.count)

        ===

        """

        for group in groupedExcerpts {
            output += export(
                bookTitle: group.title,
                author: group.author,
                excerpts: group.excerpts,
                exportedAt: exportedAt
            )
            output += "\n\n"
        }

        return output
    }

    private func sanitizedFilenameComponent(_ value: String, fallback: String) -> String {
        let unsafeCharacters = CharacterSet(charactersIn: "/\\?%*|\"<>:\n\r\t")
            .union(.controlCharacters)
        let pieces = value.components(separatedBy: unsafeCharacters)
        let sanitized = pieces
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        guard !sanitized.isEmpty else {
            return fallback
        }
        return String(sanitized.prefix(80))
    }
}

private struct ExcerptExportBookKey: Hashable {
    var bookId: UUID
    var title: String
    var author: String

    init(_ excerpt: ExcerptEntity) {
        bookId = excerpt.bookId
        title = excerpt.bookTitleSnapshot
        author = excerpt.authorDisplaySnapshot
    }
}
