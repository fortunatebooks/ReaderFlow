import Foundation
import Observation

@MainActor
@Observable
final class LibraryViewModel {
    private(set) var books: [LibraryBook]

    init(books: [LibraryBook] = []) {
        self.books = LibraryBookListFilter.visibleBooks(
            from: books,
            searchText: "",
            sortMode: .recent
        )
    }

    var hasBooks: Bool {
        !books.isEmpty
    }

    func addImportedBook(_ book: LibraryBook) {
        books.append(book)
        books = LibraryBookListFilter.visibleBooks(
            from: books,
            searchText: "",
            sortMode: .recent
        )
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
