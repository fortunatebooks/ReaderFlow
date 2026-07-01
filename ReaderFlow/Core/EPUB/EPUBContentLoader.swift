import Foundation
import SwiftSoup

struct EPUBContentLoader {
    private let fileManager: FileManager
    private let sanitizer: EPUBContentSanitizer

    init(
        fileManager: FileManager = .default,
        sanitizer: EPUBContentSanitizer = EPUBContentSanitizer()
    ) {
        self.fileManager = fileManager
        self.sanitizer = sanitizer
    }

    func loadChapters(
        expandedRootURL: URL,
        package: EPUBPackageDocument,
        bookId: UUID
    ) throws -> [ContinuousDocumentChapter] {
        let resolver = package.resourceResolver
        return try package.readingOrder.compactMap { item in
            guard item.linear, isHTML(item.mediaType) else {
                return nil
            }

            let chapterURL = try chapterFileURL(
                for: item,
                expandedRootURL: expandedRootURL,
                resolver: resolver
            )
            let xhtml = try readXHTML(at: chapterURL, href: item.href)
            let document: Document
            do {
                document = try SwiftSoup.parse(xhtml)
            } catch {
                throw EPUBContentLoaderError.invalidXHTML(path: item.href, reason: error.localizedDescription)
            }

            guard let body = try document.body() else {
                throw EPUBContentLoaderError.missingBody(path: item.href)
            }

            try rewriteResourceReferences(
                in: body,
                baseHref: item.href,
                resolver: resolver,
                bookId: bookId
            )

            return try ContinuousDocumentChapter(
                href: item.href,
                title: chapterTitle(document: document, body: body, fallback: item.href),
                bodyHTML: sanitizer.sanitizeHTML(body.html())
            )
        }
    }

    private func isHTML(_ mediaType: String) -> Bool {
        let lowercased = mediaType.lowercased()
        return lowercased == "application/xhtml+xml"
            || lowercased == "text/html"
            || lowercased.hasSuffix("+html")
            || lowercased.contains("html")
    }

    private func chapterFileURL(
        for item: EPUBReadingOrderItem,
        expandedRootURL: URL,
        resolver: EPUBResourceResolver
    ) throws -> URL {
        guard let normalizedPath = resolver.normalizedResourcePath(item.href),
              let fileURL = fileURL(forNormalizedResourcePath: normalizedPath, rootURL: expandedRootURL)
        else {
            throw EPUBContentLoaderError.unsafeReadingOrderHref(item.href)
        }

        guard fileManager.fileExists(atPath: fileURL.path) else {
            throw EPUBContentLoaderError.missingReadingOrderFile(path: item.href)
        }
        return fileURL
    }

    private func fileURL(forNormalizedResourcePath normalizedPath: String, rootURL: URL) -> URL? {
        let resourcePath = normalizedPath
            .split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map(String.init) ?? normalizedPath
        let root = rootURL.standardizedFileURL
        let candidate = resourcePath
            .split(separator: "/")
            .reduce(root) { partialURL, component in
                partialURL.appendingPathComponent(String(component))
            }
            .standardizedFileURL

        guard candidate.path == root.path || candidate.path.hasPrefix(root.path + "/") else {
            return nil
        }
        return candidate
    }

    private func readXHTML(at url: URL, href: String) throws -> String {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw EPUBContentLoaderError.unreadableXHTML(path: href)
        }

        if let string = String(data: data, encoding: .utf8) {
            return string
        }
        if let string = String(data: data, encoding: .utf16) {
            return string
        }
        if let string = String(data: data, encoding: .isoLatin1) {
            return string
        }
        throw EPUBContentLoaderError.unreadableXHTML(path: href)
    }

    private func rewriteResourceReferences(
        in body: Element,
        baseHref: String,
        resolver: EPUBResourceResolver,
        bookId: UUID
    ) throws {
        try rewriteURLAttribute("href", selector: "[href]", in: body, baseHref: baseHref, resolver: resolver, bookId: bookId)
        try rewriteURLAttribute("src", selector: "[src]", in: body, baseHref: baseHref, resolver: resolver, bookId: bookId)
        try rewriteURLAttribute("poster", selector: "[poster]", in: body, baseHref: baseHref, resolver: resolver, bookId: bookId)
        try rewriteURLAttribute(
            "xlink:href",
            selector: "[xlink\\:href]",
            in: body,
            baseHref: baseHref,
            resolver: resolver,
            bookId: bookId
        )
        try rewriteSrcsetAttributes(in: body, baseHref: baseHref, resolver: resolver, bookId: bookId)
        try rewriteInlineStyles(in: body, baseHref: baseHref, resolver: resolver, bookId: bookId)
        try rewriteStyleElements(in: body, baseHref: baseHref, resolver: resolver, bookId: bookId)
    }

    private func rewriteURLAttribute(
        _ attribute: String,
        selector: String,
        in body: Element,
        baseHref: String,
        resolver: EPUBResourceResolver,
        bookId: UUID
    ) throws {
        for element in try body.select(selector).array() {
            let value = try element.attr(attribute)
            if shouldPreserveLocalFragment(value) {
                continue
            }
            if let readerURL = readerURL(for: value, bookId: bookId, relativeTo: baseHref, resolver: resolver) {
                try element.attr(attribute, readerURL.absoluteString)
            } else {
                try element.removeAttr(attribute)
            }
        }
    }

    private func rewriteSrcsetAttributes(
        in body: Element,
        baseHref: String,
        resolver: EPUBResourceResolver,
        bookId: UUID
    ) throws {
        for element in try body.select("[srcset]").array() {
            let rewrittenCandidates = try element.attr("srcset")
                .split(separator: ",")
                .compactMap { candidate -> String? in
                    let parts = candidate
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .split(maxSplits: 1, whereSeparator: \.isWhitespace)
                        .map(String.init)
                    guard let href = parts.first,
                          let readerURL = readerURL(for: href, bookId: bookId, relativeTo: baseHref, resolver: resolver)
                    else {
                        return nil
                    }

                    if parts.count == 2 {
                        return readerURL.absoluteString + " " + parts[1]
                    }
                    return readerURL.absoluteString
                }

            if rewrittenCandidates.isEmpty {
                try element.removeAttr("srcset")
            } else {
                try element.attr("srcset", rewrittenCandidates.joined(separator: ", "))
            }
        }
    }

    private func rewriteInlineStyles(
        in body: Element,
        baseHref: String,
        resolver: EPUBResourceResolver,
        bookId: UUID
    ) throws {
        for element in try body.select("[style]").array() {
            let rewritten = try rewriteCSSURLs(
                element.attr("style"),
                baseHref: baseHref,
                resolver: resolver,
                bookId: bookId
            )
            if rewritten.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                try element.removeAttr("style")
            } else {
                try element.attr("style", rewritten)
            }
        }
    }

    private func rewriteStyleElements(
        in body: Element,
        baseHref: String,
        resolver: EPUBResourceResolver,
        bookId: UUID
    ) throws {
        for element in try body.select("style").array() {
            let rewritten = try rewriteCSSURLs(
                element.html(),
                baseHref: baseHref,
                resolver: resolver,
                bookId: bookId
            )
            try element.html(rewritten)
        }
    }

    private func rewriteCSSURLs(
        _ css: String,
        baseHref: String,
        resolver: EPUBResourceResolver,
        bookId: UUID
    ) -> String {
        let pattern = #"url\(\s*(['"]?)(.*?)\1\s*\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return css
        }

        let input = css as NSString
        var output = css
        for match in regex.matches(in: css, range: NSRange(location: 0, length: input.length)).reversed() {
            guard match.numberOfRanges >= 3 else { continue }
            let rawValue = input.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !shouldPreserveLocalFragment(rawValue),
                  let rewritten = readerURL(for: rawValue, bookId: bookId, relativeTo: baseHref, resolver: resolver)
            else {
                output = (output as NSString).replacingCharacters(in: match.range, with: "url()")
                continue
            }

            output = (output as NSString).replacingCharacters(in: match.range, with: "url('\(rewritten.absoluteString)')")
        }

        return output
    }

    private func shouldPreserveLocalFragment(_ value: String) -> Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("#")
    }

    private func readerURL(
        for href: String,
        bookId: UUID,
        relativeTo baseHref: String,
        resolver: EPUBResourceResolver
    ) -> URL? {
        let trimmed = href.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.hasPrefix("//"),
              URLComponents(string: trimmed)?.scheme == nil
        else {
            return nil
        }
        return resolver.readerURL(for: trimmed, bookId: bookId, relativeTo: baseHref)
    }

    private func chapterTitle(document: Document, body: Element, fallback: String) -> String {
        if let title = try? document.title().trimmingCharacters(in: .whitespacesAndNewlines),
           !title.isEmpty
        {
            return title
        }

        if let heading = try? body.select("h1, h2, h3, h4, h5, h6").first(),
           let headingText = try? heading.text().trimmingCharacters(in: .whitespacesAndNewlines),
           !headingText.isEmpty
        {
            return headingText
        }

        return fallback
    }
}

enum EPUBContentLoaderError: LocalizedError, Equatable {
    case unsafeReadingOrderHref(String)
    case missingReadingOrderFile(path: String)
    case unreadableXHTML(path: String)
    case missingBody(path: String)
    case invalidXHTML(path: String, reason: String)

    var errorDescription: String? {
        switch self {
        case let .unsafeReadingOrderHref(href):
            "ReaderFlow rejected an unsafe EPUB reading order href: \(href)."
        case let .missingReadingOrderFile(path):
            "ReaderFlow could not find the EPUB content document at \(path)."
        case let .unreadableXHTML(path):
            "ReaderFlow could not read the EPUB content document at \(path)."
        case let .missingBody(path):
            "ReaderFlow could not find a body element in the EPUB content document at \(path)."
        case let .invalidXHTML(path, reason):
            "ReaderFlow could not parse the EPUB content document at \(path): \(reason)"
        }
    }
}
