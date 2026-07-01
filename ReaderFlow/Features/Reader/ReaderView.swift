import SwiftData
import SwiftUI
import UIKit

struct ReaderView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query private var settings: [ReaderSettingsEntity]
    @Query(sort: \ExcerptEntity.sortProgress) private var excerpts: [ExcerptEntity]
    let book: BookEntity
    let initialPosition: ReaderInitialPosition?
    let initialHighlightId: UUID?
    let initialProgressValue: Double
    private let routineProgressSaveInterval: TimeInterval = 1

    @State private var pendingInitialNavigationRequest: ReaderNavigationRequest?
    init(book: BookEntity, initialPosition: ReaderInitialPosition? = nil, initialHighlightId: UUID? = nil) {
        self.book = book
        self.initialPosition = initialPosition
        self.initialHighlightId = initialHighlightId
        let restorePosition = initialPosition ?? book.readerInitialPosition
        _pendingInitialNavigationRequest = State(initialValue: restorePosition.map {
            ReaderNavigationRequest(id: UUID(), position: $0, highlightId: initialHighlightId)
        })
        initialProgressValue = restorePosition?.progress ?? book.readingProgress
    }

    @State private var isScrolling = false
    @State private var speed: Double = 25
    @State private var showControls = true
    @State private var confirmationText: String?
    @State private var readerHTML: String?
    @State private var readerLoadError: String?
    @State private var showingTableOfContents = false
    @State private var showingSettings = false
    @State private var navigationRequest: ReaderNavigationRequest?
    @State private var progressRequestID: UUID?
    @State private var lastProgressMessage: ReaderProgressMessage?
    @State private var lastProgressSaveAt: Date?
    @State private var trailingProgressSaveTask: Task<Void, Never>?
    @State private var shouldPersistNextProgressImmediately = false
    @State private var bridgeToken = UUID().uuidString
    @State private var hasCompletedInitialAppear = false

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
                initialProgress: effectiveInitialProgress,
                navigationRequest: readerHTML == nil ? nil : effectiveNavigationRequest,
                highlights: readerHighlightPayloads,
                progressRequestID: progressRequestID,
                speed: $speed,
                isScrolling: $isScrolling,
                onProgress: saveProgress,
                onSelection: saveSelection,
                onReady: readerDidBecomeReady,
                onTap: toggleReaderPlayback,
                onSpeedAdjustment: adjustSpeed,
                onScrollStateChanged: readerScrollStateChanged,
                onNavigationApplied: readerNavigationApplied
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
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    showingTableOfContents = true
                } label: {
                    Label("Contents", systemImage: "list.bullet")
                }
                .disabled(tableOfContentsEntries.isEmpty)

                NavigationLink {
                    BookExcerptsView(book: book) { excerpt in
                        navigateToExcerpt(excerpt)
                    }
                } label: {
                    Label("Excerpts", systemImage: "text.quote")
                }
            }
        }
        .onAppear {
            ensureSettings()
            speed = activeSettings.autoscrollSpeed
            guard !hasCompletedInitialAppear else { return }
            hasCompletedInitialAppear = true
            isScrolling = initialPosition == nil && book.lastOpenedAt != nil
            book.lastOpenedAt = .now
            book.lastOpenedSortKey = .now
            try? modelContext.save()
            showExcerptJumpConfirmationIfNeeded()
        }
        .onDisappear {
            trailingProgressSaveTask?.cancel()
            if let lastProgressMessage {
                persistProgress(lastProgressMessage)
            }
            pauseReaderAndFlushProgress(animated: false)
        }
        .task(id: readerDocumentReloadID) {
            await loadReaderHTML()
        }
        .onChange(of: speed) { _, newSpeed in
            activeSettings.autoscrollSpeed = newSpeed
            try? modelContext.save()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase != .active {
                pauseReaderAndFlushProgress(animated: false)
            }
        }
        .sheet(isPresented: $showingTableOfContents) {
            NavigationStack {
                TableOfContentsListView(entries: tableOfContentsEntries) { entry in
                    navigateToTableOfContentsEntry(entry)
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            NavigationStack {
                SettingsView()
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 12) {
            HStack {
                Button {
                    setReaderScrolling(!isScrolling)
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

            Button {
                pauseReaderAndFlushProgress()
                showingSettings = true
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

    private var effectiveInitialProgress: Double {
        guard initialPosition == nil else {
            return initialProgressValue
        }
        return book.readerInitialPosition?.progress ?? book.readingProgress
    }

    private var effectiveNavigationRequest: ReaderNavigationRequest? {
        navigationRequest
            ?? pendingInitialNavigationRequest
    }

    private var tableOfContentsEntries: [TableOfContentsEntry] {
        guard let data = book.tableOfContentsJSON,
              let payload = try? JSONDecoder().decode(TableOfContentsPayload.self, from: data)
        else {
            return []
        }
        return payload.entries
    }

    private var readerHighlightPayloads: [ReaderHighlightPayload] {
        excerpts.compactMap { excerpt in
            guard excerpt.bookId == book.id else {
                return nil
            }
            return excerpt.readerHighlightPayload(
                expectedBookId: book.id,
                expectedBookFingerprint: book.contentFingerprint
            )
        }
    }

    @MainActor
    private func loadReaderHTML() async {
        readerLoadError = nil
        readerHTML = nil

        let bookId = book.id
        let title = book.title
        let contentFingerprint = book.contentFingerprint
        let languageCode = book.languageCode
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
                    bookFingerprint: contentFingerprint,
                    languageCode: languageCode
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
        guard readerHTML != nil else { return }
        lastProgressMessage = progress
        if shouldPersistNextProgressImmediately {
            shouldPersistNextProgressImmediately = false
            persistProgress(progress)
            return
        }
        guard shouldPersistRoutineProgress else {
            scheduleTrailingProgressSave()
            return
        }
        persistProgress(progress)
    }

    private func persistProgress(_ progress: ReaderProgressMessage) {
        trailingProgressSaveTask?.cancel()
        trailingProgressSaveTask = nil
        lastProgressSaveAt = .now
        book.readingProgress = progress.boundedTotalProgression
        book.lastLocatorJSON = progress.encodedLocator(bookId: book.id, bookFingerprint: book.contentFingerprint)
        book.lastOpenedAt = .now
        book.lastOpenedSortKey = .now
        try? modelContext.save()
    }

    private var shouldPersistRoutineProgress: Bool {
        guard let lastProgressSaveAt else {
            return true
        }
        return Date.now.timeIntervalSince(lastProgressSaveAt) >= routineProgressSaveInterval
    }

    private func scheduleTrailingProgressSave() {
        trailingProgressSaveTask?.cancel()
        let delay = trailingProgressSaveDelay
        trailingProgressSaveTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }
            guard let lastProgressMessage else { return }
            persistProgress(lastProgressMessage)
        }
    }

    private var trailingProgressSaveDelay: TimeInterval {
        guard let lastProgressSaveAt else {
            return 0
        }
        return max(0.05, routineProgressSaveInterval - Date.now.timeIntervalSince(lastProgressSaveAt))
    }

    private func readerDidBecomeReady() {
        if isScrolling {
            showControls = false
        }
    }

    private func showExcerptJumpConfirmationIfNeeded() {
        guard initialPosition != nil else { return }
        showControls = true
        confirmationText = "Excerpt location"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            if confirmationText == "Excerpt location" {
                confirmationText = nil
            }
        }
    }

    private func toggleReaderPlayback() {
        setReaderScrolling(!isScrolling)
    }

    private func setReaderScrolling(_ isRunning: Bool, animated: Bool = true) {
        let updates = {
            isScrolling = isRunning
            showControls = !isRunning
        }
        if animated {
            withAnimation(.easeOut(duration: 0.2), updates)
        } else {
            updates()
        }
        if !isRunning {
            requestProgressFlush()
        }
    }

    private func pauseReaderAndFlushProgress(animated: Bool = true) {
        setReaderScrolling(false, animated: animated)
    }

    private func requestProgressFlush() {
        guard readerHTML != nil else { return }
        shouldPersistNextProgressImmediately = true
        progressRequestID = UUID()
        if let lastProgressMessage {
            persistProgress(lastProgressMessage)
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

    private func readerScrollStateChanged(_ state: ReaderScrollStateMessage) {
        if isScrolling != state.running {
            isScrolling = state.running
        }

        if state.running {
            withAnimation(.easeOut(duration: 0.2)) {
                showControls = false
            }
            return
        }

        withAnimation(.easeOut(duration: 0.2)) {
            showControls = true
        }
        requestProgressFlush()
        switch state.reason {
        case "manualScroll":
            showTransientReaderMessage("Paused")
        case "end":
            showTransientReaderMessage("End of book", duration: 1.8)
        default:
            break
        }
    }

    private func navigateToTableOfContentsEntry(_ entry: TableOfContentsEntry) {
        navigationRequest = ReaderNavigationRequest(id: UUID(), href: entry.href)
        showingTableOfContents = false
    }

    private func navigateToExcerpt(_ excerpt: ExcerptEntity) {
        let position = excerpt.readerInitialPosition
        isScrolling = false
        showControls = true
        navigationRequest = ReaderNavigationRequest(
            id: UUID(),
            position: position,
            highlightId: excerpt.id
        )
        confirmationText = "Excerpt location"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            if confirmationText == "Excerpt location" {
                confirmationText = nil
            }
        }
    }

    private func readerNavigationApplied(_ requestID: UUID) {
        if pendingInitialNavigationRequest?.id == requestID {
            pendingInitialNavigationRequest = nil
        }
        if navigationRequest?.id == requestID {
            navigationRequest = nil
        }
    }

    private func showTransientReaderMessage(_ message: String, duration: TimeInterval = 1.2) {
        confirmationText = message
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            if confirmationText == message {
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

private struct TableOfContentsListView: View {
    let entries: [TableOfContentsEntry]
    let onSelect: (TableOfContentsEntry) -> Void

    private var flattenedEntries: [FlattenedTableOfContentsEntry] {
        FlattenedTableOfContentsEntry.flatten(entries)
    }

    var body: some View {
        List(flattenedEntries) { item in
            Button {
                onSelect(item.entry)
            } label: {
                HStack(spacing: 10) {
                    Color.clear
                        .frame(width: CGFloat(item.level * 14), height: 1)
                    Text(item.entry.title)
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Contents")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct FlattenedTableOfContentsEntry: Identifiable {
    var id: String
    var entry: TableOfContentsEntry
    var level: Int

    static func flatten(_ entries: [TableOfContentsEntry]) -> [FlattenedTableOfContentsEntry] {
        flatten(entries, level: 0, path: "")
    }

    private static func flatten(
        _ entries: [TableOfContentsEntry],
        level: Int,
        path: String
    ) -> [FlattenedTableOfContentsEntry] {
        entries.enumerated().flatMap { index, entry in
            let entryPath = path.isEmpty ? "\(index)" : "\(path).\(index)"
            return [
                FlattenedTableOfContentsEntry(id: entryPath + entry.id, entry: entry, level: level),
            ] + flatten(entry.children, level: level + 1, path: entryPath)
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

private extension ReaderNavigationRequest {
    init(id: UUID, position: ReaderInitialPosition, highlightId: UUID? = nil) {
        self.init(
            id: id,
            href: position.href,
            chapterProgression: position.chapterProgression,
            fallbackProgress: position.progress,
            scrollY: position.scrollY,
            documentHeight: position.documentHeight,
            highlightId: highlightId
        )
    }
}

private extension ReaderProgressMessage {
    var boundedTotalProgression: Double {
        bounded(totalProgression)
    }

    func encodedLocator(bookId: UUID, bookFingerprint: String) -> Data? {
        let locator = ReaderLocator(
            bookId: bookId,
            bookFingerprint: bookFingerprint,
            spineIndex: max(0, spineIndex ?? 0),
            href: href ?? "",
            chapterTitle: chapterTitle,
            chapterProgression: bounded(chapterProgression ?? totalProgression),
            totalProgression: bounded(totalProgression),
            scrollY: max(0, scrollY),
            documentHeight: max(1, documentHeight),
            textQuote: nil,
            domTextPath: nil,
            contentHash: nil,
            readiumLocatorJSON: nil,
            createdAt: .now
        )
        return try? JSONEncoder().encode(locator)
    }

    private func bounded(_ value: Double) -> Double {
        min(1, max(0, value))
    }
}
