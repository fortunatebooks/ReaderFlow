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
    private let bridgeToken = UUID().uuidString

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
                html: ReaderHTMLBuilder.placeholderHTML(book: book, settings: activeSettings, bridgeToken: bridgeToken),
                expectedBridgeToken: bridgeToken,
                bookResourceRootURL: bookResourceRootURL,
                speed: $speed,
                isScrolling: $isScrolling,
                onProgress: saveProgress,
                onSelection: saveSelection
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
        .onTapGesture {
            withAnimation(.easeOut(duration: 0.2)) {
                isScrolling.toggle()
                showControls = !isScrolling
            }
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

    private var bookResourceRootURL: URL? {
        guard let store = try? AppFileStore() else { return nil }
        return store.booksURL
            .appending(path: book.id.uuidString, directoryHint: .isDirectory)
            .appending(path: "expanded", directoryHint: .isDirectory)
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            confirmationText = nil
        }
    }
}
