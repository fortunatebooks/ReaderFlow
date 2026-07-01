import Foundation
import SwiftData

@ModelActor
actor ReaderFlowDatabase {
    func save() throws {
        try modelContext.save()
    }
}
