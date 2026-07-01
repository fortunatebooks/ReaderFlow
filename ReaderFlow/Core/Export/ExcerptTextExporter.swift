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

        for excerpt in sortedExcerpts(excerpts) {
            let selectedText = normalizedBodyText(excerpt.selectedText)
            let contextBefore = normalizedInlineText(excerpt.contextBefore)
            let contextAfter = normalizedInlineText(excerpt.contextAfter)
            let contextSelection = normalizedInlineText(selectedText)
            output += """
            Chapter: \(excerpt.chapterTitle ?? "Unknown")
            Location: \(locationDescription(for: excerpt))
            Saved: \(excerpt.createdAt.formatted(date: .abbreviated, time: .shortened))

            \(selectedText)

            """
            if !contextBefore.isEmpty || !contextAfter.isEmpty {
                output += "Context: ...\(contextBefore) [excerpt] \(contextSelection) [/excerpt] \(contextAfter)...\n\n"
            }
            output += "---\n\n"
        }

        return normalizedLineEndings(output)
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
                    excerpts: sortedExcerpts(excerpts)
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

    private func sortedExcerpts(_ excerpts: [ExcerptEntity]) -> [ExcerptEntity] {
        excerpts.sorted { lhs, rhs in
            let lhsProgress = sortableProgress(lhs.sortProgress)
            let rhsProgress = sortableProgress(rhs.sortProgress)
            if lhsProgress != rhsProgress {
                return lhsProgress < rhsProgress
            }
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private func locationDescription(for excerpt: ExcerptEntity) -> String {
        guard let progress = boundedProgress(excerpt.sortProgress) else {
            return "Unknown"
        }
        return "\(Int(progress * 100))%"
    }

    private func sortableProgress(_ progress: Double) -> Double {
        boundedProgress(progress) ?? .infinity
    }

    private func boundedProgress(_ progress: Double) -> Double? {
        guard progress.isFinite else {
            return nil
        }
        return min(1, max(0, progress))
    }

    private func normalizedBodyText(_ text: String) -> String {
        let normalizedLines = normalizedLineEndings(text)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { normalizedInlineText(String($0)) }
            .joined(separator: "\n")
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        return normalizedLines.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedInlineText(_ text: String) -> String {
        normalizedLineEndings(text)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedLineEndings(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
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
