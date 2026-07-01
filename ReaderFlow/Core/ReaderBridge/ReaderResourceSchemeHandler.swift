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
        let parts = urlPathParts(url)
        guard !parts.isEmpty else { return nil }
        if parts.first == "fonts" {
            return resolveBundledFont(parts: Array(parts.dropFirst()))
        }
        guard parts.count == 1 else { return nil }
        let filename = parts[0]
        let resourceName = (filename as NSString).deletingPathExtension
        let resourceExtension = (filename as NSString).pathExtension
        return bundle.url(
            forResource: resourceName,
            withExtension: resourceExtension.isEmpty ? nil : resourceExtension,
            subdirectory: "ReaderWeb"
        )
    }

    private func resolveBundledFont(parts: [String]) -> URL? {
        guard parts.count >= 2 else { return nil }
        let filename = parts.last ?? ""
        let resourceName = (filename as NSString).deletingPathExtension
        let resourceExtension = (filename as NSString).pathExtension
        let subdirectory = (["Fonts"] + parts.dropLast()).joined(separator: "/")
        return bundle.url(
            forResource: resourceName,
            withExtension: resourceExtension.isEmpty ? nil : resourceExtension,
            subdirectory: subdirectory
        )
    }

    private func resolveBookResource(_ url: URL) -> URL? {
        guard let bookResourceRootURL else { return nil }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        let parts = ReaderResourcePath.encodedParts(fromPercentEncodedPath: components.percentEncodedPath)
        guard parts.count >= 2 else { return nil }
        let bookIdPart = parts[0].removingPercentEncoding ?? parts[0]
        guard expectedBookId.map({ $0.uuidString == bookIdPart }) ?? true else {
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

    private func urlPathParts(_ url: URL) -> [String] {
        ReaderResourcePath.parts(fromPercentEncodedPath: url.percentEncodedPath)
    }

    private func urlPathParts(_ percentEncodedPath: String) -> [String] {
        ReaderResourcePath.parts(fromPercentEncodedPath: percentEncodedPath)
    }

    private func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "otf":
            return "font/otf"
        case "ttf":
            return "font/ttf"
        case "woff":
            return "font/woff"
        case "woff2":
            return "font/woff2"
        default:
            break
        }
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

enum ReaderResourcePath {
    static func parts(fromPercentEncodedPath percentEncodedPath: String) -> [String] {
        validatedParts(fromPercentEncodedPath: percentEncodedPath).map(\.decoded)
    }

    static func encodedParts(fromPercentEncodedPath percentEncodedPath: String) -> [String] {
        validatedParts(fromPercentEncodedPath: percentEncodedPath).map(\.encoded)
    }

    private static func validatedParts(fromPercentEncodedPath percentEncodedPath: String) -> [PathPart] {
        var parts: [PathPart] = []
        for rawPart in percentEncodedPath.split(separator: "/") {
            let encodedPart = String(rawPart)
            guard let decodedPart = String(rawPart).removingPercentEncoding,
                  isSafePathPart(decodedPart)
            else {
                return []
            }
            parts.append(PathPart(encoded: encodedPart, decoded: decodedPart))
        }
        return parts
    }

    private static func isSafePathPart(_ value: String) -> Bool {
        !value.isEmpty
            && value != "."
            && value != ".."
            && !value.contains("/")
            && !value.contains("\\")
            && !value.contains("\u{0}")
    }

    private struct PathPart {
        var encoded: String
        var decoded: String
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
