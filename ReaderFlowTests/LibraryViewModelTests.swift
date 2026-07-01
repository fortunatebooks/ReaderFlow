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
        let older = Date(timeIntervalSinceReferenceDate: 100)
        let newer = Date(timeIntervalSinceReferenceDate: 200)

        let viewModel = LibraryViewModel(
            books: [
                LibraryBook(title: "Older", author: "Author", lastOpenedAt: older),
                LibraryBook(title: "Never Opened", author: "Author"),
                LibraryBook(title: "Newer", author: "Author", lastOpenedAt: newer),
            ]
        )

        XCTAssertEqual(viewModel.books.map(\.title), ["Newer", "Older", "Never Opened"])
    }
}
