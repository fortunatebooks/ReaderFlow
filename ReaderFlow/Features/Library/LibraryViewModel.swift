import Foundation
import Observation

@MainActor
@Observable
final class LibraryViewModel {
    private(set) var books: [LibraryBook]

    init(books: [LibraryBook] = []) {
        self.books = books.sortedByRecentActivity()
    }

    var hasBooks: Bool {
        !books.isEmpty
    }

    func addImportedBook(_ book: LibraryBook) {
        books.append(book)
        books = books.sortedByRecentActivity()
    }
}

private extension [LibraryBook] {
    func sortedByRecentActivity() -> [LibraryBook] {
        sorted { lhs, rhs in
            switch (lhs.lastOpenedAt, rhs.lastOpenedAt) {
            case let (lhsDate?, rhsDate?):
                lhsDate > rhsDate
            case (_?, nil):
                true
            case (nil, _?):
                false
            case (nil, nil):
                lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
        }
    }
}

extension LibraryViewModel {
    static let preview = LibraryViewModel(
        books: [
            LibraryBook(
                title: "The Continuous Reader",
                author: "ReaderFlow",
                progress: 0.42,
                lastOpenedAt: .now
            ),
            LibraryBook(
                title: "Proofing Notes",
                author: "A. Reviewer",
                progress: 0.12
            ),
        ]
    )
}
