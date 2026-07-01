import SwiftUI

struct AppRootView: View {
    var body: some View {
        LibraryView()
            .task {
                cleanStaleExportFiles()
            }
    }

    private func cleanStaleExportFiles() {
        guard let store = try? AppFileStore() else {
            return
        }
        try? store.removeExportFiles(olderThan: Date.now.addingTimeInterval(-Self.exportFileRetentionInterval))
    }

    private static let exportFileRetentionInterval: TimeInterval = 24 * 60 * 60
}
