import Foundation
import SwiftSoup

struct EPUBContentLoader {
    private let fileManager: FileManager
    private let sanitizer: EPUBContentSanitizer
    private let maximumStylesheetBytes = 512 * 1024
    private let maximumStylesheetImportDepth = 4

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
        let chapterItems = package.readingOrder.filter { $0.linear && isHTML($0.mediaType) }
        let internalLinkTargets = internalLinkTargets(for: chapterItems, resolver: resolver)

        return try chapterItems.enumerated().map { index, item in
            let chapterID = "rf-spine-\(index)"
            let currentTarget = internalLinkTarget(for: item.href, resolver: resolver, targets: internalLinkTargets)
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

            if let currentTarget {
                try namespaceElementIDs(in: body, prefix: currentTarget.fragmentPrefix)
            }
            try rewriteResourceReferences(
                in: body,
                baseHref: item.href,
                resolver: resolver,
                bookId: bookId,
                internalLinkTargets: internalLinkTargets,
                currentTarget: currentTarget,
                chapterID: chapterID
            )
            let authorStyles = authorStylesheetHTML(
                document: document,
                baseHref: item.href,
                expandedRootURL: expandedRootURL,
                resolver: resolver,
                bookId: bookId,
                chapterID: chapterID
            )
            let chapterHTML = [authorStyles, body.html()]
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: "\n")

            return try ContinuousDocumentChapter(
                href: item.href,
                title: chapterTitle(document: document, body: body, fallback: item.href),
                bodyHTML: sanitizer.sanitizeHTML(chapterHTML)
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
              let fileURL = EPUBResourceResolver.fileURL(forNormalizedResourcePath: normalizedPath, rootURL: expandedRootURL)
        else {
            throw EPUBContentLoaderError.unsafeReadingOrderHref(item.href)
        }

        guard fileManager.fileExists(atPath: fileURL.path) else {
            throw EPUBContentLoaderError.missingReadingOrderFile(path: item.href)
        }
        return fileURL
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
        bookId: UUID,
        internalLinkTargets: [String: InternalLinkTarget],
        currentTarget: InternalLinkTarget?,
        chapterID: String
    ) throws {
        try rewriteURLAttribute(
            "href",
            selector: "[href]",
            in: body,
            baseHref: baseHref,
            resolver: resolver,
            bookId: bookId,
            internalLinkTargets: internalLinkTargets,
            currentTarget: currentTarget
        )
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
        try rewriteStyleElements(in: body, baseHref: baseHref, resolver: resolver, bookId: bookId, chapterID: chapterID)
    }

    private func authorStylesheetHTML(
        document: Document,
        baseHref: String,
        expandedRootURL: URL,
        resolver: EPUBResourceResolver,
        bookId: UUID,
        chapterID: String
    ) -> String {
        guard let links = try? document.select("link[href]").array() else {
            return ""
        }

        return links.compactMap { element -> String? in
            guard let rel = try? element.attr("rel").lowercased(),
                  let href = try? element.attr("href")
            else {
                return nil
            }
            let relTokens = rel.split(whereSeparator: \.isWhitespace).map(String.init)
            guard relTokens.contains("stylesheet"),
                  !relTokens.contains("alternate"),
                  let css = stylesheetCSS(
                      href: href,
                      baseHref: baseHref,
                      expandedRootURL: expandedRootURL,
                      resolver: resolver,
                      bookId: bookId
                  ),
                  !css.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                return nil
            }

            let media = (try? element.attr("media").trimmingCharacters(in: .whitespacesAndNewlines)) ?? ""
            let scopedCSS = wrapCSSForMediaIfNeeded(
                scopeAuthorCSS(css, chapterID: chapterID),
                media: media
            )
            return """
            <style data-readerflow-author-stylesheet="\(href.htmlEscaped)">
            \(scopedCSS.escapedForStyleElement)
            </style>
            """
        }
        .joined(separator: "\n")
    }

    private func rewriteURLAttribute(
        _ attribute: String,
        selector: String,
        in body: Element,
        baseHref: String,
        resolver: EPUBResourceResolver,
        bookId: UUID,
        internalLinkTargets: [String: InternalLinkTarget] = [:],
        currentTarget: InternalLinkTarget? = nil
    ) throws {
        for element in try body.select(selector).array() {
            let value = try element.attr(attribute)
            if attribute == "href",
               shouldPreserveLocalFragment(value),
               let currentTarget
            {
                try element.attr(attribute, fragmentHref(value, target: currentTarget))
                continue
            }
            if shouldPreserveLocalFragment(value) {
                continue
            }
            if attribute == "href" {
                if let internalHref = internalDocumentHref(
                    for: value,
                    baseHref: baseHref,
                    resolver: resolver,
                    targets: internalLinkTargets
                ) {
                    try element.attr(attribute, internalHref)
                    continue
                }
                if isHTMLResourceHref(value, baseHref: baseHref, resolver: resolver) {
                    try element.removeAttr(attribute)
                    continue
                }
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
        bookId: UUID,
        chapterID: String
    ) throws {
        for element in try body.select("style").array() {
            let rewritten = try rewriteCSSURLs(
                element.html(),
                baseHref: baseHref,
                resolver: resolver,
                bookId: bookId
            )
            try element.html(scopeAuthorCSS(rewritten, chapterID: chapterID).escapedForStyleElement)
        }
    }

    private func stylesheetCSS(
        href: String,
        baseHref: String,
        expandedRootURL: URL,
        resolver: EPUBResourceResolver,
        bookId: UUID
    ) -> String? {
        var importStack: Set<String> = []
        return stylesheetCSS(
            href: href,
            baseHref: baseHref,
            expandedRootURL: expandedRootURL,
            resolver: resolver,
            bookId: bookId,
            importStack: &importStack,
            depth: 0
        )
    }

    private func stylesheetCSS(
        href: String,
        baseHref: String,
        expandedRootURL: URL,
        resolver: EPUBResourceResolver,
        bookId: UUID,
        importStack: inout Set<String>,
        depth: Int
    ) -> String? {
        guard depth <= maximumStylesheetImportDepth,
              let normalizedPath = resolver.normalizedResourcePath(href, relativeTo: baseHref)
        else {
            return nil
        }

        let resourcePath = resourcePath(from: normalizedPath)
        guard !importStack.contains(resourcePath),
              let fileURL = EPUBResourceResolver.fileURL(forNormalizedResourcePath: resourcePath, rootURL: expandedRootURL),
              fileManager.fileExists(atPath: fileURL.path),
              let css = readStylesheet(at: fileURL)
        else {
            return nil
        }
        importStack.insert(resourcePath)
        defer {
            importStack.remove(resourcePath)
        }

        let inlinedImports = inlineCSSImports(
            css,
            baseHref: normalizedPath,
            expandedRootURL: expandedRootURL,
            resolver: resolver,
            bookId: bookId,
            importStack: &importStack,
            depth: depth
        )
        return rewriteCSSURLs(inlinedImports, baseHref: normalizedPath, resolver: resolver, bookId: bookId)
    }

    private func readStylesheet(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url),
              data.count <= maximumStylesheetBytes
        else {
            return nil
        }

        return String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .utf16)
            ?? String(data: data, encoding: .isoLatin1)
    }

    private func inlineCSSImports(
        _ css: String,
        baseHref: String,
        expandedRootURL: URL,
        resolver: EPUBResourceResolver,
        bookId: UUID,
        importStack: inout Set<String>,
        depth: Int
    ) -> String {
        let patterns = [
            (
                pattern: #"@import\s+(?:url\(\s*)?(['"])(.*?)\1\s*\)?\s*([^;]*);"#,
                hrefGroup: 2,
                mediaGroup: 3
            ),
            (
                pattern: #"@import\s+url\(\s*([^'"\)\s][^\)]*?)\s*\)\s*([^;]*);"#,
                hrefGroup: 1,
                mediaGroup: 2
            ),
        ]
        var output = css
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern.pattern, options: [.caseInsensitive]) else {
                continue
            }
            output = replaceCSSImports(
                in: output,
                regex: regex,
                hrefGroup: pattern.hrefGroup,
                mediaGroup: pattern.mediaGroup,
                baseHref: baseHref,
                expandedRootURL: expandedRootURL,
                resolver: resolver,
                bookId: bookId,
                importStack: &importStack,
                depth: depth
            )
        }
        return output
    }

    private func replaceCSSImports(
        in css: String,
        regex: NSRegularExpression,
        hrefGroup: Int,
        mediaGroup: Int,
        baseHref: String,
        expandedRootURL: URL,
        resolver: EPUBResourceResolver,
        bookId: UUID,
        importStack: inout Set<String>,
        depth: Int
    ) -> String {
        let input = css as NSString
        var output = css
        for match in regex.matches(in: css, range: NSRange(location: 0, length: input.length)).reversed() {
            guard match.numberOfRanges > max(hrefGroup, mediaGroup) else { continue }
            let hrefRange = match.range(at: hrefGroup)
            let mediaRange = match.range(at: mediaGroup)
            guard hrefRange.location != NSNotFound else { continue }
            let href = input.substring(with: hrefRange).trimmingCharacters(in: .whitespacesAndNewlines)
            let media = mediaRange.location == NSNotFound
                ? ""
                : input.substring(with: mediaRange).trimmingCharacters(in: .whitespacesAndNewlines)

            guard let importedCSS = stylesheetCSS(
                href: href,
                baseHref: baseHref,
                expandedRootURL: expandedRootURL,
                resolver: resolver,
                bookId: bookId,
                importStack: &importStack,
                depth: depth + 1
            ) else {
                output = (output as NSString).replacingCharacters(in: match.range, with: "")
                continue
            }

            let replacement: String = if media.isEmpty {
                importedCSS
            } else if let sanitizedMedia = sanitizedMediaQuery(media) {
                "@media \(sanitizedMedia) {\n\(importedCSS)\n}"
            } else {
                ""
            }
            output = (output as NSString).replacingCharacters(in: match.range, with: replacement)
        }
        return output
    }

    private func wrapCSSForMediaIfNeeded(_ css: String, media: String) -> String {
        let trimmedMedia = media.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMedia.isEmpty,
              trimmedMedia.lowercased() != "all"
        else {
            return css
        }
        guard let sanitizedMedia = sanitizedMediaQuery(trimmedMedia) else {
            return ""
        }
        return "@media \(sanitizedMedia) {\n\(css)\n}"
    }

    private func sanitizedMediaQuery(_ media: String) -> String? {
        let trimmed = media.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.range(of: #"^[A-Za-z0-9_\-\s,():./]+$"#, options: .regularExpression) != nil
        else {
            return nil
        }
        return trimmed
    }

    private func scopeAuthorCSS(_ css: String, chapterID: String) -> String {
        scopeCSSBlock(css, chapterID: chapterID)
    }

    private func scopeCSSBlock(_ css: String, chapterID: String) -> String {
        var output = ""
        var cursor = css.startIndex

        while let openBrace = nextRuleOpenBrace(in: css, from: cursor) {
            let selectorRange = cursor ..< openBrace
            let selector = String(css[selectorRange])
            guard let closeBrace = matchingCloseBrace(in: css, openingAt: openBrace) else {
                return output
            }

            let bodyStart = css.index(after: openBrace)
            let body = String(css[bodyStart ..< closeBrace])
            output += scopedRule(selector: selector, body: body, chapterID: chapterID)
            cursor = css.index(after: closeBrace)
        }

        output += css[cursor...]
        return output
    }

    private func nextRuleOpenBrace(in css: String, from startIndex: String.Index) -> String.Index? {
        var index = startIndex
        var stringDelimiter: Character?
        var isEscaped = false
        var isInComment = false

        while index < css.endIndex {
            let character = css[index]
            let nextIndex = css.index(after: index)
            let nextCharacter = nextIndex < css.endIndex ? css[nextIndex] : nil

            if isInComment {
                if character == "*", nextCharacter == "/" {
                    isInComment = false
                    index = css.index(after: nextIndex)
                    continue
                }
                index = nextIndex
                continue
            }

            if let delimiter = stringDelimiter {
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == delimiter {
                    stringDelimiter = nil
                }
                index = nextIndex
                continue
            }

            if character == "/", nextCharacter == "*" {
                isInComment = true
                index = css.index(after: nextIndex)
                continue
            }

            if character == "\"" || character == "'" {
                stringDelimiter = character
                index = nextIndex
                continue
            }

            if character == "{" {
                return index
            }
            index = nextIndex
        }
        return nil
    }

    private func scopedRule(selector: String, body: String, chapterID: String) -> String {
        let trimmedSelector = selector.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSelector.isEmpty,
              !trimmedSelector.contains("{"),
              !trimmedSelector.contains("}")
        else {
            return ""
        }

        let lowercased = trimmedSelector.lowercased()
        if lowercased.hasPrefix("@media")
            || lowercased.hasPrefix("@supports")
            || lowercased.hasPrefix("@container")
        {
            return "\(selector){\(scopeCSSBlock(body, chapterID: chapterID))}"
        }

        if lowercased.hasPrefix("@font-face")
            || lowercased.hasPrefix("@keyframes")
            || lowercased.hasPrefix("@-webkit-keyframes")
        {
            return "\(selector){\(body)}"
        }

        if lowercased.hasPrefix("@page") {
            return ""
        }

        let scopedSelectors = selector
            .split(separator: ",", omittingEmptySubsequences: false)
            .map { scopeSelector(String($0), chapterID: chapterID) }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: ", ")

        guard !scopedSelectors.isEmpty else {
            return ""
        }
        return "\(scopedSelectors){\(body)}"
    }

    private func matchingCloseBrace(in css: String, openingAt openBrace: String.Index) -> String.Index? {
        var depth = 0
        var index = openBrace
        var stringDelimiter: Character?
        var isEscaped = false
        var isInComment = false

        while index < css.endIndex {
            let character = css[index]
            let nextIndex = css.index(after: index)
            let nextCharacter = nextIndex < css.endIndex ? css[nextIndex] : nil

            if isInComment {
                if character == "*", nextCharacter == "/" {
                    isInComment = false
                    index = css.index(after: nextIndex)
                    continue
                }
                index = nextIndex
                continue
            }

            if let delimiter = stringDelimiter {
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == delimiter {
                    stringDelimiter = nil
                }
                index = nextIndex
                continue
            }

            if character == "/", nextCharacter == "*" {
                isInComment = true
                index = css.index(after: nextIndex)
                continue
            }

            if character == "\"" || character == "'" {
                stringDelimiter = character
                index = nextIndex
                continue
            }

            switch css[index] {
            case "{":
                depth += 1
            case "}":
                depth -= 1
                if depth == 0 {
                    return index
                }
            default:
                break
            }
            index = nextIndex
        }
        return nil
    }

    private func scopeSelector(_ selector: String, chapterID: String) -> String {
        let leadingWhitespace = String(selector.prefix { $0.isWhitespace })
        let trimmed = selector.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ""
        }

        let scope = "#\(chapterID)"
        let lowercased = trimmed.lowercased()
        if lowercased == "html" || lowercased == "body" || lowercased == ":root" {
            return leadingWhitespace + scope
        }

        for rootSelector in ["html", "body", ":root"] {
            if let replaced = replacingRootSelector(rootSelector, in: trimmed, scope: scope) {
                return leadingWhitespace + replaced
            }
        }

        if trimmed.hasPrefix(scope) {
            return leadingWhitespace + trimmed
        }
        return leadingWhitespace + scope + " " + trimmed
    }

    private func replacingRootSelector(_ rootSelector: String, in selector: String, scope: String) -> String? {
        guard selector.lowercased().hasPrefix(rootSelector) else {
            return nil
        }

        let boundaryIndex = selector.index(selector.startIndex, offsetBy: rootSelector.count)
        guard boundaryIndex == selector.endIndex || isSelectorBoundary(selector[boundaryIndex]) else {
            return nil
        }
        return scope + String(selector[boundaryIndex...])
    }

    private func isSelectorBoundary(_ character: Character) -> Bool {
        String(character).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || [">", "+", "~", ".", "#", ":", "["].contains(String(character))
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
            if rawValue.lowercased().hasPrefix("readerflow://") {
                continue
            }
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

    private func internalLinkTargets(
        for items: [EPUBReadingOrderItem],
        resolver: EPUBResourceResolver
    ) -> [String: InternalLinkTarget] {
        var targets: [String: InternalLinkTarget] = [:]
        for (index, item) in items.enumerated() {
            guard let normalizedPath = resolver.normalizedResourcePath(item.href) else {
                continue
            }
            let path = resourcePath(from: normalizedPath)
            if targets[path] == nil {
                let chapterID = "rf-spine-\(index)"
                targets[path] = InternalLinkTarget(chapterID: chapterID, fragmentPrefix: chapterID)
            }
        }
        return targets
    }

    private func internalLinkTarget(
        for href: String,
        resolver: EPUBResourceResolver,
        targets: [String: InternalLinkTarget]
    ) -> InternalLinkTarget? {
        guard let normalizedPath = resolver.normalizedResourcePath(href) else {
            return nil
        }
        return targets[resourcePath(from: normalizedPath)]
    }

    private func internalDocumentHref(
        for href: String,
        baseHref: String,
        resolver: EPUBResourceResolver,
        targets: [String: InternalLinkTarget]
    ) -> String? {
        let trimmed = href.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.hasPrefix("//"),
              URLComponents(string: trimmed)?.scheme == nil,
              let normalizedPath = resolver.normalizedResourcePath(trimmed, relativeTo: baseHref)
        else {
            return nil
        }

        let resourcePath = resourcePath(from: normalizedPath)
        guard let targetID = targets[resourcePath] else {
            return nil
        }
        return fragmentHref(normalizedPath, target: targetID)
    }

    private func isHTMLResourceHref(
        _ href: String,
        baseHref: String,
        resolver: EPUBResourceResolver
    ) -> Bool {
        let trimmed = href.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.hasPrefix("//"),
              URLComponents(string: trimmed)?.scheme == nil,
              let normalizedPath = resolver.normalizedResourcePath(trimmed, relativeTo: baseHref)
        else {
            return false
        }

        let path = resourcePath(from: normalizedPath).lowercased()
        return path.hasSuffix(".xhtml") || path.hasSuffix(".html") || path.hasSuffix(".htm")
    }

    private func resourcePath(from normalizedPath: String) -> String {
        normalizedPath
            .split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map(String.init) ?? normalizedPath
    }

    private func namespaceElementIDs(in body: Element, prefix: String) throws {
        for element in try body.select("[id]").array() {
            let id = try element.attr("id").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty else {
                continue
            }
            try element.attr("id", namespacedFragmentID(id, prefix: prefix))
        }
    }

    private func fragmentHref(_ href: String, target: InternalLinkTarget) -> String {
        guard let fragment = hrefFragment(from: href) else {
            return "#\(target.chapterID)"
        }
        return "#\(namespacedFragmentID(fragment, prefix: target.fragmentPrefix))"
    }

    private func hrefFragment(from href: String) -> String? {
        let parts = href.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count > 1, !parts[1].isEmpty else {
            return nil
        }
        return String(parts[1])
    }

    private func namespacedFragmentID(_ fragment: String, prefix: String) -> String {
        prefix + "-" + fragment
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

private extension String {
    var escapedForStyleElement: String {
        replacingOccurrences(of: "</", with: "<\\/")
    }
}

private struct InternalLinkTarget: Hashable {
    var chapterID: String
    var fragmentPrefix: String
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
