import Foundation

enum LibrarySortMode: String, CaseIterable, Identifiable {
    case recent
    case title
    case author
    case imported

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .recent:
            "Recent"
        case .title:
            "Title"
        case .author:
            "Author"
        case .imported:
            "Imported"
        }
    }
}

protocol LibraryListBook {
    var libraryTitle: String { get }
    var libraryAuthor: String { get }
    var libraryImportedAt: Date { get }
    var libraryLastOpenedAt: Date? { get }
}

enum LibraryBookListFilter {
    static func visibleBooks<Book: LibraryListBook>(
        from books: [Book],
        searchText: String,
        sortMode: LibrarySortMode
    ) -> [Book] {
        filteredBooks(from: books, searchText: searchText)
            .sorted(using: sortMode)
    }

    private static func filteredBooks<Book: LibraryListBook>(from books: [Book], searchText: String) -> [Book] {
        let normalizedQuery = searchText.normalizedLibrarySearchText
        guard !normalizedQuery.isEmpty else {
            return books
        }
        return books.filter { book in
            book.libraryTitle.normalizedLibrarySearchText.contains(normalizedQuery)
                || book.libraryAuthor.normalizedLibrarySearchText.contains(normalizedQuery)
        }
    }
}

private extension Array where Element: LibraryListBook {
    func sorted(using sortMode: LibrarySortMode) -> [Element] {
        sorted { lhs, rhs in
            switch sortMode {
            case .recent:
                compareRecent(lhs, rhs)
            case .title:
                compareText(lhs.libraryTitle, rhs.libraryTitle, tieBreaker: { compareText(lhs.libraryAuthor, rhs.libraryAuthor) })
            case .author:
                compareText(lhs.libraryAuthor, rhs.libraryAuthor, tieBreaker: { compareText(lhs.libraryTitle, rhs.libraryTitle) })
            case .imported:
                lhs.libraryImportedAt != rhs.libraryImportedAt
                    ? lhs.libraryImportedAt > rhs.libraryImportedAt
                    : compareText(lhs.libraryTitle, rhs.libraryTitle)
            }
        }
    }

    private func compareRecent(_ lhs: Element, _ rhs: Element) -> Bool {
        let lhsDate = lhs.libraryLastOpenedAt ?? lhs.libraryImportedAt
        let rhsDate = rhs.libraryLastOpenedAt ?? rhs.libraryImportedAt
        if lhsDate != rhsDate {
            return lhsDate > rhsDate
        }
        return compareText(lhs.libraryTitle, rhs.libraryTitle)
    }

    private func compareText(_ lhs: String, _ rhs: String, tieBreaker: (() -> Bool)? = nil) -> Bool {
        let comparison = lhs.localizedStandardCompare(rhs)
        if comparison != .orderedSame {
            return comparison == .orderedAscending
        }
        return tieBreaker?() ?? false
    }
}

private extension String {
    var normalizedLibrarySearchText: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}

extension LibraryBook: LibraryListBook {
    var libraryTitle: String {
        title
    }

    var libraryAuthor: String {
        author
    }

    var libraryImportedAt: Date {
        importedAt
    }

    var libraryLastOpenedAt: Date? {
        lastOpenedAt
    }
}

extension BookEntity: LibraryListBook {
    var libraryTitle: String {
        title
    }

    var libraryAuthor: String {
        authorDisplay
    }

    var libraryImportedAt: Date {
        importedAt
    }

    var libraryLastOpenedAt: Date? {
        lastOpenedSortKey ?? lastOpenedAt
    }
}
