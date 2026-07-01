import SwiftData
import SwiftUI
import UIKit

struct BookExcerptsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ExcerptEntity.createdAt, order: .reverse) private var excerpts: [ExcerptEntity]
    let book: BookEntity

    private var bookExcerpts: [ExcerptEntity] {
        excerpts
            .filter { $0.bookId == book.id }
            .sorted { $0.sortProgress < $1.sortProgress }
    }

    var body: some View {
        List {
            if bookExcerpts.isEmpty {
                ContentUnavailableView("No Excerpts", systemImage: "text.quote", description: Text("Saved passages from this book will appear here."))
            } else {
                Section {
                    ForEach(bookExcerpts) { excerpt in
                        ExcerptRow(excerpt: excerpt)
                            .swipeActions {
                                Button(role: .destructive) {
                                    modelContext.delete(excerpt)
                                    try? modelContext.save()
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
            }
        }
        .navigationTitle("Excerpts")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(
                    item: ExcerptTextExportFile.book(
                        bookTitle: book.title,
                        author: book.authorDisplay,
                        excerpts: bookExcerpts
                    ),
                    preview: SharePreview(ExcerptTextExporter().bookExportFilename(bookTitle: book.title))
                ) {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .disabled(bookExcerpts.isEmpty)
            }
        }
    }
}

struct ArchivedExcerptsView: View {
    @Query(sort: \ExcerptEntity.createdAt, order: .reverse) private var excerpts: [ExcerptEntity]

    private var archivedGroups: [(key: ExcerptBookGroupKey, excerpts: [ExcerptEntity])] {
        Dictionary(grouping: excerpts.filter { !$0.sourceBookAvailable }, by: ExcerptBookGroupKey.init)
            .map { ($0.key, $0.value.sorted { $0.sortProgress < $1.sortProgress }) }
            .sorted(by: sortBookGroups)
    }

    var body: some View {
        List {
            if archivedGroups.isEmpty {
                ContentUnavailableView("No Archived Excerpts", systemImage: "archivebox", description: Text("Excerpts from deleted local books remain available here."))
            } else {
                ForEach(archivedGroups, id: \.key) { group in
                    NavigationLink {
                        ArchivedBookExcerptsView(title: group.key.title, excerpts: group.excerpts)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(group.key.title)
                                .font(.headline)
                            Text("\(group.key.author) · \(group.excerpts.count) excerpts")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Archived")
    }
}

struct AllExcerptsView: View {
    @Query(sort: \ExcerptEntity.createdAt, order: .reverse) private var excerpts: [ExcerptEntity]

    private var excerptGroups: [(key: ExcerptBookGroupKey, excerpts: [ExcerptEntity])] {
        Dictionary(grouping: excerpts, by: ExcerptBookGroupKey.init)
            .map { ($0.key, $0.value.sorted { $0.sortProgress < $1.sortProgress }) }
            .sorted(by: sortBookGroups)
    }

    var body: some View {
        List {
            if excerptGroups.isEmpty {
                ContentUnavailableView("No Excerpts", systemImage: "text.quote", description: Text("Saved passages from your books will appear here."))
            } else {
                ForEach(excerptGroups, id: \.key) { group in
                    Section {
                        ForEach(group.excerpts) { excerpt in
                            ExcerptRow(excerpt: excerpt)
                        }
                    } header: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(group.key.title)
                            Text(group.key.author)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Saved Excerpts")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(
                    item: ExcerptTextExportFile.library(excerpts: excerpts),
                    preview: SharePreview(ExcerptTextExporter().libraryExportFilename())
                ) {
                    Label("Export All", systemImage: "square.and.arrow.up")
                }
                .disabled(excerpts.isEmpty)
            }
        }
    }
}

private struct ExcerptBookGroupKey: Hashable {
    var bookId: UUID
    var title: String
    var author: String

    init(_ excerpt: ExcerptEntity) {
        bookId = excerpt.bookId
        title = excerpt.bookTitleSnapshot
        author = excerpt.authorDisplaySnapshot
    }
}

private func sortBookGroups(
    _ lhs: (key: ExcerptBookGroupKey, excerpts: [ExcerptEntity]),
    _ rhs: (key: ExcerptBookGroupKey, excerpts: [ExcerptEntity])
) -> Bool {
    let titleComparison = lhs.key.title.localizedStandardCompare(rhs.key.title)
    if titleComparison != .orderedSame {
        return titleComparison == .orderedAscending
    }
    let authorComparison = lhs.key.author.localizedStandardCompare(rhs.key.author)
    if authorComparison != .orderedSame {
        return authorComparison == .orderedAscending
    }
    return lhs.key.bookId.uuidString < rhs.key.bookId.uuidString
}

private struct ArchivedBookExcerptsView: View {
    let title: String
    let excerpts: [ExcerptEntity]

    var body: some View {
        List(excerpts) { excerpt in
            ExcerptRow(excerpt: excerpt)
        }
        .navigationTitle(title)
        .toolbar {
            ShareLink(
                item: ExcerptTextExportFile.book(
                    bookTitle: title,
                    author: excerpts.first?.authorDisplaySnapshot ?? "Unknown Author",
                    excerpts: excerpts
                ),
                preview: SharePreview(ExcerptTextExporter().bookExportFilename(bookTitle: title))
            ) {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .disabled(excerpts.isEmpty)
        }
    }
}

private struct ExcerptRow: View {
    let excerpt: ExcerptEntity

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(excerpt.selectedText)
                .font(.body)
                .lineLimit(5)
            HStack(spacing: 8) {
                Text(excerpt.chapterTitle ?? "Unknown chapter")
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text("\(Int(excerpt.sortProgress * 100))%")
                Text("·")
                Text(excerpt.createdAt, style: .date)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .contextMenu {
            ShareLink(
                item: ExcerptTextExportFile.singleExcerpt(excerpt),
                preview: SharePreview(ExcerptTextExporter().singleExcerptExportFilename(bookTitle: excerpt.bookTitleSnapshot))
            ) {
                Label("Share Excerpt", systemImage: "square.and.arrow.up")
            }
            Button {
                UIPasteboard.general.string = ExcerptTextExporter().export(excerpt: excerpt)
            } label: {
                Label("Copy Excerpt", systemImage: "doc.on.doc")
            }
        }
    }
}
