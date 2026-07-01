import SwiftData
import SwiftUI

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \BookEntity.titleSortKey) private var books: [BookEntity]
    @Query(sort: \ExcerptEntity.createdAt, order: .reverse) private var excerpts: [ExcerptEntity]
    @State private var showingImporter = false
    @State private var importError: String?

    private var activeBooks: [BookEntity] {
        books.filter { !$0.isArchived }
            .sorted { lhs, rhs in
                (lhs.lastOpenedSortKey ?? lhs.importedAt) > (rhs.lastOpenedSortKey ?? rhs.importedAt)
            }
    }

    var body: some View {
        NavigationStack {
            Group {
                if activeBooks.isEmpty {
                    emptyState
                } else {
                    bookList
                }
            }
            .navigationTitle("ReaderFlow")
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
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingImporter = true
                    } label: {
                        Label("Import", systemImage: "plus")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
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

    private var bookList: some View {
        List {
            Section("Recent Books") {
                ForEach(activeBooks) { book in
                    NavigationLink {
                        ReaderView(book: book)
                    } label: {
                        BookRow(book: book)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            archive(book)
                        } label: {
                            Label("Delete Local Copy", systemImage: "trash")
                        }
                    }
                }
            }
        }
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

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 6)
                .fill(.tint.opacity(0.18))
                .frame(width: 48, height: 68)
                .overlay {
                    Image(systemName: "book.closed")
                        .foregroundStyle(.tint)
                }

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
            }
        }
        .padding(.vertical, 4)
    }
}
