import Foundation
import SwiftSoup

struct EPUBTableOfContentsParser {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func parseTableOfContents(
        expandedRootURL: URL,
        package: EPUBPackageDocument
    ) throws -> [TableOfContentsEntry] {
        guard let navItem = package.manifest.first(where: { $0.properties.contains("nav") }) else {
            return fallbackEntries(package: package)
        }
        guard let navPath = package.resourceResolver.normalizedResourcePath(navItem.href),
              let navURL = EPUBResourceResolver.fileURL(forNormalizedResourcePath: navPath, rootURL: expandedRootURL),
              fileManager.fileExists(atPath: navURL.path)
        else {
            return fallbackEntries(package: package)
        }

        let data = try Data(contentsOf: navURL)
        guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) ?? String(data: data, encoding: .isoLatin1) else {
            return fallbackEntries(package: package)
        }

        let document = try SwiftSoup.parse(html)
        guard let list = try tocList(in: document) else {
            return fallbackEntries(package: package)
        }

        let entries = try parseEntries(in: list, navHref: navItem.href, resolver: package.resourceResolver)
        return entries.isEmpty ? fallbackEntries(package: package) : entries
    }

    private func tocList(in document: Document) throws -> Element? {
        let navs = try document.select("nav").array()
        guard let tocNav = navs.first(where: { nav in
            let epubType = (try? nav.attr("epub:type")) ?? ""
            let type = (try? nav.attr("type")) ?? ""
            return epubType.split(whereSeparator: \.isWhitespace).map(String.init).contains("toc") || type == "toc"
        }) ?? navs.first else {
            return nil
        }

        return try tocNav.select("ol, ul").first()
    }

    private func parseEntries(
        in list: Element,
        navHref: String,
        resolver: EPUBResourceResolver
    ) throws -> [TableOfContentsEntry] {
        try list.children().array().compactMap { child in
            guard try child.tagName().lowercased() == "li" else {
                return nil
            }
            return try parseEntry(in: child, navHref: navHref, resolver: resolver)
        }
    }

    private func parseEntry(
        in listItem: Element,
        navHref: String,
        resolver: EPUBResourceResolver
    ) throws -> TableOfContentsEntry? {
        guard let anchor = try listItem.select("a[href]").first() else {
            return nil
        }

        let title = try anchor.text().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty,
              let href = try resolver.normalizedResourcePath(anchor.attr("href"), relativeTo: navHref)
        else {
            return nil
        }

        let childLists = try listItem.children().array().filter { child in
            let tagName = ((try? child.tagName()) ?? "").lowercased()
            return tagName == "ol" || tagName == "ul"
        }
        let children = try childLists.flatMap { childList in
            try parseEntries(in: childList, navHref: navHref, resolver: resolver)
        }

        return TableOfContentsEntry(title: title, href: href, children: children)
    }

    private func fallbackEntries(package: EPUBPackageDocument) -> [TableOfContentsEntry] {
        package.readingOrder
            .filter(\.linear)
            .compactMap { item in
                guard let href = package.resourceResolver.normalizedResourcePath(item.href) else {
                    return nil
                }
                return TableOfContentsEntry(title: item.href, href: href, children: [])
            }
    }
}
