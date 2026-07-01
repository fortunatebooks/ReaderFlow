import SwiftData
import SwiftUI
import UIKit

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \BookEntity.titleSortKey) private var books: [BookEntity]
    @Query(sort: \ExcerptEntity.createdAt, order: .reverse) private var excerpts: [ExcerptEntity]
    @State private var showingImporter = false
    @State private var importError: String?
    @State private var searchText = ""
    @State private var sortMode: LibrarySortMode = .recent
    @State private var pendingArchiveBook: BookEntity?

    private var activeBooks: [BookEntity] {
        books.filter { !$0.isArchived }
    }

    private var visibleBooks: [BookEntity] {
        LibraryBookListFilter.visibleBooks(
            from: activeBooks,
            searchText: searchText,
            sortMode: sortMode
        )
    }

    var body: some View {
        NavigationStack {
            Group {
                if activeBooks.isEmpty {
                    emptyState
                } else if visibleBooks.isEmpty {
                    noMatchesState
                } else {
                    bookList
                }
            }
            .navigationTitle("ReaderFlow")
            .searchable(text: $searchText, prompt: "Search books or authors")
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    NavigationLink {
                        AllExcerptsView()
                    } label: {
                        Label("Excerpts", systemImage: "text.quote")
                    }

                    NavigationLink {
                        ArchivedExcerptsView()
                    } label: {
                        Label("Archived", systemImage: "archivebox")
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu {
                        Picker("Sort", selection: $sortMode) {
                            ForEach(LibrarySortMode.allCases) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                    } label: {
                        Label(sortMode.displayName, systemImage: "arrow.up.arrow.down")
                    }

                    Button {
                        showingImporter = true
                    } label: {
                        Label("Import", systemImage: "plus")
                    }

                    NavigationLink {
                        SettingsView()
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            }
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: [.readerFlowEPUB],
                allowsMultipleSelection: false,
                onCompletion: handleImportResult
            )
            .alert("Import Failed", isPresented: importErrorBinding) {
                Button("OK") {
                    importError = nil
                }
            } message: {
                Text(importError ?? "")
            }
            .alert("Delete Local Copy?", isPresented: archiveConfirmationBinding) {
                Button("Delete Local Copy", role: .destructive) {
                    archivePendingBook()
                }
                Button("Cancel", role: .cancel) {
                    pendingArchiveBook = nil
                }
            } message: {
                Text(archiveConfirmationMessage)
            }
            .onOpenURL { url in
                importEPUB(from: url)
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("ReaderFlow", systemImage: "book")
        } description: {
            Text("Import a DRM-free EPUB to begin.")
        } actions: {
            Button {
                showingImporter = true
            } label: {
                Label("Import EPUB", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var noMatchesState: some View {
        ContentUnavailableView {
            Label("No Matches", systemImage: "magnifyingglass")
        } description: {
            Text("No books match your search.")
        }
    }

    private var bookList: some View {
        List {
            Section(sectionTitle) {
                ForEach(visibleBooks) { book in
                    bookRow(for: book)
                }
            }
        }
    }

    private var sectionTitle: String {
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Search Results"
        }
        switch sortMode {
        case .recent:
            return "Recent Books"
        case .title, .author, .imported:
            return "All Books"
        }
    }

    private func bookRow(for book: BookEntity) -> some View {
        let bookExcerpts = excerpts(for: book)
        return NavigationLink {
            ReaderView(book: book)
        } label: {
            BookRow(book: book, excerptCount: bookExcerpts.count)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                confirmArchive(book)
            } label: {
                Label("Delete Local Copy", systemImage: "trash")
            }
        }
        .contextMenu {
            ShareLink(
                item: ExcerptTextExportFile.book(
                    bookTitle: book.title,
                    author: book.authorDisplay,
                    excerpts: bookExcerpts
                ),
                preview: SharePreview(ExcerptTextExporter().bookExportFilename(bookTitle: book.title))
            ) {
                Label("Export Excerpts", systemImage: "square.and.arrow.up")
            }
            .disabled(bookExcerpts.isEmpty)

            Button(role: .destructive) {
                confirmArchive(book)
            } label: {
                Label("Delete Local Copy", systemImage: "trash")
            }
        }
    }

    private var archiveConfirmationBinding: Binding<Bool> {
        Binding {
            pendingArchiveBook != nil
        } set: { isPresented in
            if !isPresented {
                pendingArchiveBook = nil
            }
        }
    }

    private var archiveConfirmationMessage: String {
        guard let pendingArchiveBook else {
            return "The EPUB file and extracted reader files will be removed from this device. Saved excerpts will remain available under Archived."
        }
        return "The EPUB file and extracted reader files for \"\(pendingArchiveBook.title)\" will be removed from this device. Saved excerpts will remain available under Archived."
    }

    private func confirmArchive(_ book: BookEntity) {
        pendingArchiveBook = book
    }

    private func archivePendingBook() {
        guard let pendingArchiveBook else { return }
        archive(pendingArchiveBook)
        self.pendingArchiveBook = nil
    }

    private func excerpts(for book: BookEntity) -> [ExcerptEntity] {
        excerpts
            .filter { $0.bookId == book.id }
            .sorted { $0.sortProgress < $1.sortProgress }
    }

    private var importErrorBinding: Binding<Bool> {
        Binding {
            importError != nil
        } set: { isPresented in
            if !isPresented {
                importError = nil
            }
        }
    }

    private func handleImportResult(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            importEPUB(from: url)
        } catch {
            importError = error.localizedDescription
        }
    }

    private func importEPUB(from url: URL) {
        let knownFingerprints = Set(books.map(\.contentFingerprint))
        Task {
            do {
                let draft = try await buildImportDraft(from: url, knownFingerprints: knownFingerprints)
                try saveImportedBook(draft)
            } catch {
                importError = error.localizedDescription
            }
        }
    }

    private func buildImportDraft(from url: URL, knownFingerprints: Set<String>) async throws -> ImportedEPUBDraft {
        try await Task.detached(priority: .userInitiated) {
            let store = try AppFileStore()
            return try await EPUBImportService(fileStore: store)
                .importEPUB(from: url, knownFingerprints: knownFingerprints)
        }.value
    }

    private func saveImportedBook(_ draft: ImportedEPUBDraft) throws {
        let book = BookEntity(
            id: draft.id,
            title: draft.title,
            authorDisplay: draft.authorDisplay,
            authorsJSON: draft.encodedAuthors(),
            languageCode: draft.languageCode,
            originalFileName: draft.originalFileName,
            epubFileName: draft.epubFileName,
            expandedDirectoryName: draft.expandedDirectoryName,
            coverFileName: draft.coverFileName,
            tableOfContentsJSON: draft.encodedTableOfContents(),
            fileSizeBytes: draft.fileSizeBytes,
            expandedSizeBytes: draft.preflight.expandedSizeBytes,
            xhtmlSizeBytes: draft.preflight.xhtmlSizeBytes,
            spineItemCount: draft.package.readingOrder.count,
            estimatedDomNodeCount: draft.preflight.estimatedDomNodeCount,
            imageCount: draft.preflight.imageCount,
            contentFingerprint: draft.contentFingerprint
        )

        do {
            modelContext.insert(book)
            try modelContext.save()
        } catch {
            if let store = try? AppFileStore() {
                try? store.removeBookFiles(bookId: draft.id)
            }
            throw error
        }
    }

    private func archive(_ book: BookEntity) {
        if let store = try? AppFileStore() {
            try? store.removeBookFiles(bookId: book.id)
        }
        book.isArchived = true
        book.archivedAt = .now
        book.deletedFileAt = .now
        book.importStatus = BookImportStatus.archived.rawValue
        for excerpt in excerpts where excerpt.bookId == book.id {
            excerpt.sourceBookAvailable = false
        }
        try? modelContext.save()
    }
}

private struct BookRow: View {
    let book: BookEntity
    let excerptCount: Int

    var body: some View {
        HStack(spacing: 12) {
            BookCoverThumbnail(book: book)

            VStack(alignment: .leading, spacing: 4) {
                Text(book.title)
                    .font(.headline)
                    .lineLimit(2)
                Text(book.authorDisplay)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                ProgressView(value: book.readingProgress)
                    .frame(maxWidth: 180)
                HStack(spacing: 8) {
                    Text("\(progressPercent)% read")
                    if excerptCount > 0 {
                        Text("·")
                        Text("\(excerptCount) excerpt\(excerptCount == 1 ? "" : "s")")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var progressPercent: Int {
        Int(min(1, max(0, book.readingProgress)) * 100)
    }
}

private struct BookCoverThumbnail: View {
    let book: BookEntity

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(.tint.opacity(0.18))

            if let coverImage {
                Image(uiImage: coverImage)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "book.closed")
                    .foregroundStyle(.tint)
            }
        }
        .frame(width: 48, height: 68)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var coverImage: UIImage? {
        guard let coverURL else {
            return nil
        }
        return UIImage(contentsOfFile: coverURL.path)
    }

    private var coverURL: URL? {
        guard let coverFileName = book.coverFileName,
              let store = try? AppFileStore()
        else {
            return nil
        }

        let rootURL = store.booksURL
            .appending(path: book.id.uuidString, directoryHint: .isDirectory)
            .appending(path: book.expandedDirectoryName ?? "expanded", directoryHint: .isDirectory)
        guard let candidate = EPUBResourceResolver.fileURL(forNormalizedResourcePath: coverFileName, rootURL: rootURL),
              FileManager.default.fileExists(atPath: candidate.path)
        else {
            return nil
        }
        return candidate
    }
}
