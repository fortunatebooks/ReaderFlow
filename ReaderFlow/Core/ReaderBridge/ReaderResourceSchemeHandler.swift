import Foundation
import UniformTypeIdentifiers
import WebKit

final class ReaderResourceSchemeHandler: NSObject, WKURLSchemeHandler {
    private let expectedBookId: UUID?
    private let bookResourceRootURL: URL?
    private let bundle: Bundle
    private let fileManager: FileManager

    init(
        expectedBookId: UUID? = nil,
        bookResourceRootURL: URL?,
        bundle: Bundle = .main,
        fileManager: FileManager = .default
    ) {
        self.expectedBookId = expectedBookId
        self.bookResourceRootURL = bookResourceRootURL
        self.bundle = bundle
        self.fileManager = fileManager
        super.init()
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url,
              url.scheme == "readerflow",
              let resourceURL = resolve(url)
        else {
            urlSchemeTask.didFailWithError(ReaderResourceError.notFound)
            return
        }

        do {
            let data = try Data(contentsOf: resourceURL)
            let response = URLResponse(
                url: url,
                mimeType: mimeType(for: resourceURL),
                expectedContentLength: data.count,
                textEncodingName: nil
            )
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        } catch {
            urlSchemeTask.didFailWithError(error)
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

    private func resolve(_ url: URL) -> URL? {
        switch url.host {
        case "app":
            resolveAppResource(url)
        case "book":
            resolveBookResource(url)
        default:
            nil
        }
    }

    private func resolveAppResource(_ url: URL) -> URL? {
        let resourceName = url.deletingPathExtension().lastPathComponent
        let resourceExtension = url.pathExtension
        return bundle.url(
            forResource: resourceName,
            withExtension: resourceExtension.isEmpty ? nil : resourceExtension,
            subdirectory: "ReaderWeb"
        )
    }

    private func resolveBookResource(_ url: URL) -> URL? {
        guard let bookResourceRootURL else { return nil }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        let parts = components.percentEncodedPath
            .split(separator: "/")
            .map(String.init)
        guard parts.count >= 2 else { return nil }
        guard expectedBookId.map({ $0.uuidString == parts[0] }) ?? true else {
            return nil
        }
        let normalizedPath = parts.dropFirst().joined(separator: "/")
        guard let candidate = EPUBResourceResolver.fileURL(
            forNormalizedResourcePath: normalizedPath,
            rootURL: bookResourceRootURL
        ) else { return nil }
        guard fileManager.fileExists(atPath: candidate.path) else {
            return nil
        }
        return candidate
    }

    private func mimeType(for url: URL) -> String {
        if let type = UTType(filenameExtension: url.pathExtension),
           let mimeType = type.preferredMIMEType
        {
            return mimeType
        }
        switch url.pathExtension.lowercased() {
        case "xhtml", "html":
            return "application/xhtml+xml"
        case "css":
            return "text/css"
        case "js":
            return "text/javascript"
        case "svg":
            return "image/svg+xml"
        default:
            return "application/octet-stream"
        }
    }
}

enum ReaderResourceError: LocalizedError {
    case notFound

    var errorDescription: String? {
        switch self {
        case .notFound:
            "Reader resource was not found."
        }
    }
}
