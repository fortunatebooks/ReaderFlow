import SwiftData
import SwiftUI

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
                    item: ExcerptTextExporter().export(
                        bookTitle: book.title,
                        author: book.authorDisplay,
                        excerpts: bookExcerpts
                    )
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

    private var archivedGroups: [(title: String, excerpts: [ExcerptEntity])] {
        Dictionary(grouping: excerpts.filter { !$0.sourceBookAvailable }, by: \.bookTitleSnapshot)
            .map { ($0.key, $0.value.sorted { $0.sortProgress < $1.sortProgress }) }
            .sorted { $0.title < $1.title }
    }

    var body: some View {
        List {
            if archivedGroups.isEmpty {
                ContentUnavailableView("No Archived Excerpts", systemImage: "archivebox", description: Text("Excerpts from deleted local books remain available here."))
            } else {
                ForEach(archivedGroups, id: \.title) { group in
                    NavigationLink {
                        ArchivedBookExcerptsView(title: group.title, excerpts: group.excerpts)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(group.title)
                                .font(.headline)
                            Text("\(group.excerpts.count) excerpts")
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

    private var excerptGroups: [(title: String, excerpts: [ExcerptEntity])] {
        Dictionary(grouping: excerpts, by: \.bookTitleSnapshot)
            .map { title, excerpts in
                (title, excerpts.sorted { $0.sortProgress < $1.sortProgress })
            }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    var body: some View {
        List {
            if excerptGroups.isEmpty {
                ContentUnavailableView("No Excerpts", systemImage: "text.quote", description: Text("Saved passages from your books will appear here."))
            } else {
                ForEach(excerptGroups, id: \.title) { group in
                    Section(group.title) {
                        ForEach(group.excerpts) { excerpt in
                            ExcerptRow(excerpt: excerpt)
                        }
                    }
                }
            }
        }
        .navigationTitle("Saved Excerpts")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: ExcerptTextExporter().exportLibrary(excerpts: excerpts)) {
                    Label("Export All", systemImage: "square.and.arrow.up")
                }
                .disabled(excerpts.isEmpty)
            }
        }
    }
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
            ShareLink(item: ExcerptTextExporter().export(bookTitle: title, author: excerpts.first?.authorDisplaySnapshot ?? "Unknown Author", excerpts: excerpts)) {
                Label("Export", systemImage: "square.and.arrow.up")
            }
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
            HStack {
                Text(excerpt.chapterTitle ?? "Unknown chapter")
                Spacer()
                Text(excerpt.createdAt, style: .date)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
