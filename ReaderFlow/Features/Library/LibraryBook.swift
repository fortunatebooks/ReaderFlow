import Foundation

struct LibraryBook: Identifiable, Equatable {
    let id: UUID
    var title: String
    var author: String
    var progress: Double
    var lastOpenedAt: Date?

    init(
        id: UUID = UUID(),
        title: String,
        author: String,
        progress: Double = 0,
        lastOpenedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.progress = progress
        self.lastOpenedAt = lastOpenedAt
    }
}
