@testable import ReaderFlow
import XCTest

@MainActor
final class LibraryViewModelTests: XCTestCase {
    func testStartsWithEmptyLibrary() {
        let viewModel = LibraryViewModel()

        XCTAssertFalse(viewModel.hasBooks)
        XCTAssertEqual(viewModel.books, [])
    }

    func testSortsBooksByRecentActivity() {
        let imported = Date(timeIntervalSinceReferenceDate: 50)
        let older = Date(timeIntervalSinceReferenceDate: 100)
        let newer = Date(timeIntervalSinceReferenceDate: 200)

        let viewModel = LibraryViewModel(
            books: [
                LibraryBook(title: "Older", author: "Author", importedAt: imported, lastOpenedAt: older),
                LibraryBook(title: "Never Opened", author: "Author", importedAt: imported),
                LibraryBook(title: "Newer", author: "Author", importedAt: imported, lastOpenedAt: newer),
            ]
        )

        XCTAssertEqual(viewModel.books.map(\.title), ["Newer", "Older", "Never Opened"])
    }

    func testRecentSortUsesImportDateForNeverOpenedBooks() {
        let olderImport = Date(timeIntervalSinceReferenceDate: 100)
        let olderOpen = Date(timeIntervalSinceReferenceDate: 150)
        let newerImport = Date(timeIntervalSinceReferenceDate: 300)
        let books = [
            LibraryBook(title: "Opened Older Book", author: "Author", importedAt: olderImport, lastOpenedAt: olderOpen),
            LibraryBook(title: "Fresh Import", author: "Author", importedAt: newerImport),
        ]

        let sorted = LibraryBookListFilter.visibleBooks(from: books, searchText: "", sortMode: .recent)

        XCTAssertEqual(sorted.map(\.title), ["Fresh Import", "Opened Older Book"])
    }

    func testFiltersBooksByTitleOrAuthor() {
        let books = [
            LibraryBook(title: "Café Letters", author: "Mina"),
            LibraryBook(title: "Proofing Notes", author: "A. Reviewer"),
            LibraryBook(title: "Travel Essays", author: "José Reader"),
        ]

        let titleMatches = LibraryBookListFilter.visibleBooks(from: books, searchText: "cafe", sortMode: .title)
        let authorMatches = LibraryBookListFilter.visibleBooks(from: books, searchText: "jose", sortMode: .title)

        XCTAssertEqual(titleMatches.map(\.title), ["Café Letters"])
        XCTAssertEqual(authorMatches.map(\.title), ["Travel Essays"])
    }

    func testSortsBooksBySelectedMode() {
        let olderImport = Date(timeIntervalSinceReferenceDate: 10)
        let newerImport = Date(timeIntervalSinceReferenceDate: 20)
        let books = [
            LibraryBook(title: "Zoo", author: "Beta", importedAt: olderImport),
            LibraryBook(title: "Alpha", author: "Delta", importedAt: newerImport),
            LibraryBook(title: "Middle", author: "Alpha", importedAt: olderImport),
        ]

        let byTitle = LibraryBookListFilter.visibleBooks(from: books, searchText: "", sortMode: .title)
        let byAuthor = LibraryBookListFilter.visibleBooks(from: books, searchText: "", sortMode: .author)
        let byImported = LibraryBookListFilter.visibleBooks(from: books, searchText: "", sortMode: .imported)

        XCTAssertEqual(byTitle.map(\.title), ["Alpha", "Middle", "Zoo"])
        XCTAssertEqual(byAuthor.map(\.title), ["Middle", "Zoo", "Alpha"])
        XCTAssertEqual(byImported.map(\.title), ["Alpha", "Middle", "Zoo"])
    }
}
