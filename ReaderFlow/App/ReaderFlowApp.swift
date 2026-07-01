import SwiftData
import SwiftUI

@main
struct ReaderFlowApp: App {
    var body: some Scene {
        WindowGroup {
            AppRootView()
        }
        .modelContainer(for: [
            BookEntity.self,
            ExcerptEntity.self,
            ReaderSettingsEntity.self,
        ])
    }
}
