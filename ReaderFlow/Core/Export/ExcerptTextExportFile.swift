import CoreTransferable
import Foundation
import UniformTypeIdentifiers

struct ExcerptTextExportFile: Transferable {
    var filename: String
    var text: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .plainText) { export in
            let store = try AppFileStore()
            let fileURL = try store.writeExportFile(named: export.filename, contents: export.text)
            return SentTransferredFile(fileURL)
        }
    }

    static func book(bookTitle: String, author: String, excerpts: [ExcerptEntity], exportedAt: Date = .now) -> ExcerptTextExportFile {
        let exporter = ExcerptTextExporter()
        return ExcerptTextExportFile(
            filename: exporter.bookExportFilename(bookTitle: bookTitle),
            text: exporter.export(bookTitle: bookTitle, author: author, excerpts: excerpts, exportedAt: exportedAt)
        )
    }

    static func library(excerpts: [ExcerptEntity], exportedAt: Date = .now) -> ExcerptTextExportFile {
        let exporter = ExcerptTextExporter()
        return ExcerptTextExportFile(
            filename: exporter.libraryExportFilename(),
            text: exporter.exportLibrary(excerpts: excerpts, exportedAt: exportedAt)
        )
    }

    static func singleExcerpt(_ excerpt: ExcerptEntity, exportedAt: Date = .now) -> ExcerptTextExportFile {
        let exporter = ExcerptTextExporter()
        return ExcerptTextExportFile(
            filename: exporter.singleExcerptExportFilename(bookTitle: excerpt.bookTitleSnapshot),
            text: exporter.export(excerpt: excerpt, exportedAt: exportedAt)
        )
    }
}
