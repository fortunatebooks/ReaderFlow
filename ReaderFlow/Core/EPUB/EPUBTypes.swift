import Foundation
import UniformTypeIdentifiers

extension UTType {
    static var readerFlowEPUB: UTType {
        UTType("org.idpf.epub-container") ?? UTType(filenameExtension: "epub") ?? .data
    }
}

enum EPUBImportError: LocalizedError {
    case securityScopeUnavailable
    case copyFailed
    case unsupported

    var errorDescription: String? {
        switch self {
        case .securityScopeUnavailable:
            "ReaderFlow could not access this file."
        case .copyFailed:
            "ReaderFlow could not copy this EPUB."
        case .unsupported:
            "This file is not a supported EPUB."
        }
    }
}
