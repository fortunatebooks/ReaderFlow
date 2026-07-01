import SwiftData
import SwiftUI
import UIKit

struct ReaderView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settings: [ReaderSettingsEntity]
    let book: BookEntity

    @State private var isScrolling = false
    @State private var speed: Double = 25
    @State private var showControls = true
    @State private var confirmationText: String?
    @State private var readerHTML: String?
    @State private var readerLoadError: String?
    @State private var bridgeToken = UUID().uuidString

    private var activeSettings: ReaderSettingsEntity {
        if let existing = settings.first {
            existing
        } else {
            ReaderSettingsEntity()
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ReaderWebView(
                html: currentReaderHTML,
                expectedBridgeToken: bridgeToken,
                expectedBookId: book.id,
                bookResourceRootURL: bookResourceRootURL,
                initialProgress: book.readingProgress,
                speed: $speed,
                isScrolling: $isScrolling,
                onProgress: saveProgress,
                onSelection: saveSelection,
                onReady: readerDidBecomeReady,
                onTap: toggleReaderPlayback,
                onSpeedAdjustment: adjustSpeed
            )
            .ignoresSafeArea()

            if showControls {
                controls
                    .padding()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if let confirmationText {
                Text(confirmationText)
                    .font(.callout.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.thinMaterial, in: Capsule())
                    .padding(.bottom, 92)
            }

            if let readerLoadError {
                Text(readerLoadError)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .padding(.bottom, 140)
            }
        }
        .navigationTitle(book.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    BookExcerptsView(book: book)
                } label: {
                    Label("Excerpts", systemImage: "text.quote")
                }
            }
        }
        .onAppear {
            ensureSettings()
            speed = activeSettings.autoscrollSpeed
            isScrolling = book.lastOpenedAt != nil
            book.lastOpenedAt = .now
            book.lastOpenedSortKey = .now
            try? modelContext.save()
        }
        .task(id: readerDocumentReloadID) {
            await loadReaderHTML()
        }
        .onChange(of: speed) { _, newSpeed in
            activeSettings.autoscrollSpeed = newSpeed
            try? modelContext.save()
        }
    }

    private var controls: some View {
        VStack(spacing: 12) {
            HStack {
                Button {
                    isScrolling.toggle()
                } label: {
                    Label(isScrolling ? "Pause" : "Start", systemImage: isScrolling ? "pause.fill" : "play.fill")
                }
                .buttonStyle(.borderedProminent)

                Slider(value: $speed, in: 5 ... 120) {
                    Text("Speed")
                }
                Text("\(Int(speed))")
                    .font(.caption.monospacedDigit())
                    .frame(width: 34, alignment: .trailing)
            }

            NavigationLink {
                SettingsView()
            } label: {
                Label("Reader Settings", systemImage: "textformat.size")
                    .font(.callout)
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private var currentReaderHTML: String {
        readerHTML ?? ReaderHTMLBuilder.placeholderHTML(
            book: book,
            settings: activeSettings,
            bridgeToken: bridgeToken
        )
    }

    private var readerDocumentReloadID: String {
        [
            book.id.uuidString,
            book.expandedDirectoryName ?? "expanded",
            activeSettings.theme,
            activeSettings.fontFamily,
            String(format: "%.2f", activeSettings.textSize),
            String(format: "%.2f", activeSettings.lineHeight),
            String(format: "%.2f", activeSettings.marginScale),
        ].joined(separator: "|")
    }

    private var bookResourceRootURL: URL? {
        expandedRootURL(bookId: book.id, expandedDirectoryName: book.expandedDirectoryName)
    }

    @MainActor
    private func loadReaderHTML() async {
        readerLoadError = nil
        readerHTML = nil

        let bookId = book.id
        let title = book.title
        let contentFingerprint = book.contentFingerprint
        let expandedDirectoryName = book.expandedDirectoryName
        let documentSettings = ReaderDocumentSettings(activeSettings)
        let currentBridgeToken = bridgeToken

        guard let expandedRootURL = expandedRootURL(bookId: bookId, expandedDirectoryName: expandedDirectoryName) else {
            readerLoadError = ReaderDocumentLoadError.missingExpandedDirectory.localizedDescription
            return
        }

        do {
            let html = try await Task.detached(priority: .userInitiated) {
                let package = try EPUBPackageParser().parseExpandedEPUB(at: expandedRootURL)
                let chapters = try EPUBContentLoader().loadChapters(
                    expandedRootURL: expandedRootURL,
                    package: package,
                    bookId: bookId
                )
                guard !chapters.isEmpty else {
                    throw ReaderDocumentLoadError.emptyReadingOrder
                }

                return ContinuousDocumentBuilder(
                    sanitizer: EPUBContentSanitizer(),
                    resolver: package.resourceResolver
                )
                .buildDocument(
                    title: title,
                    chapters: chapters,
                    settings: documentSettings,
                    bridgeToken: currentBridgeToken,
                    bookId: bookId,
                    bookFingerprint: contentFingerprint
                )
            }.value

            guard !Task.isCancelled else { return }
            readerHTML = html
        } catch {
            guard !Task.isCancelled else { return }
            readerLoadError = error.localizedDescription
        }
    }

    private func expandedRootURL(bookId: UUID, expandedDirectoryName: String?) -> URL? {
        guard let store = try? AppFileStore() else { return nil }
        return store.booksURL
            .appending(path: bookId.uuidString, directoryHint: .isDirectory)
            .appending(path: expandedDirectoryName ?? "expanded", directoryHint: .isDirectory)
    }

    private func ensureSettings() {
        guard settings.isEmpty else { return }
        modelContext.insert(ReaderSettingsEntity())
        try? modelContext.save()
    }

    private func saveProgress(_ progress: ReaderProgressMessage) {
        book.readingProgress = progress.totalProgression
        book.lastOpenedAt = .now
        book.lastOpenedSortKey = .now
        try? modelContext.save()
    }

    private func readerDidBecomeReady() {
        if isScrolling {
            showControls = false
        }
    }

    private func toggleReaderPlayback() {
        withAnimation(.easeOut(duration: 0.2)) {
            isScrolling.toggle()
            showControls = !isScrolling
        }
    }

    private func adjustSpeed(by delta: Double) {
        let adjustedSpeed = min(120, max(5, speed + delta))
        guard adjustedSpeed != speed else { return }
        speed = adjustedSpeed
        confirmationText = "Speed \(Int(adjustedSpeed))"
        if activeSettings.hapticsEnabled {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            if confirmationText?.hasPrefix("Speed ") == true {
                confirmationText = nil
            }
        }
    }

    private func saveSelection(_ selection: ReaderSelectionPayload) {
        let encoder = JSONEncoder()
        let locatorData = (try? encoder.encode(selection.locator)) ?? Data()
        let excerpt = ExcerptEntity(
            id: selection.highlightId,
            bookId: book.id,
            bookTitleSnapshot: book.title,
            authorDisplaySnapshot: book.authorDisplay,
            chapterTitle: selection.locator.chapterTitle,
            selectedText: selection.selectedText,
            contextBefore: selection.contextBefore,
            contextAfter: selection.contextAfter,
            locatorJSON: locatorData,
            copiedToClipboard: activeSettings.autoCopyHighlights,
            sortProgress: selection.locator.totalProgression
        )
        modelContext.insert(excerpt)
        try? modelContext.save()
        confirmationText = activeSettings.autoCopyHighlights ? "Excerpt saved and copied" : "Excerpt saved"
        if activeSettings.autoCopyHighlights {
            UIPasteboard.general.string = selection.selectedText
        }
        if activeSettings.hapticsEnabled {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            confirmationText = nil
        }
    }
}

private enum ReaderDocumentLoadError: LocalizedError {
    case missingExpandedDirectory
    case emptyReadingOrder

    var errorDescription: String? {
        switch self {
        case .missingExpandedDirectory:
            "ReaderFlow could not find this book's extracted EPUB files."
        case .emptyReadingOrder:
            "ReaderFlow could not find readable chapters in this EPUB."
        }
    }
}
