import Foundation

struct EPUBResourceResolver {
    let packageRoot: String

    func normalizedResourcePath(_ href: String, relativeTo basePath: String? = nil) -> String? {
        guard let components = URLComponents(string: href), components.scheme == nil else {
            return nil
        }

        let rawPath = href.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? href
        guard let decodedPath = rawPath.removingPercentEncoding,
              !decodedPath.hasPrefix("/")
        else {
            return nil
        }

        let rootParts = pathParts(packageRoot)
        var resolvedParts = rootParts
        let rootDepth = resolvedParts.count

        if let basePath {
            var baseParts = pathParts(basePath.removingPercentEncoding ?? basePath)
            if baseParts.starts(with: rootParts) {
                baseParts.removeFirst(rootParts.count)
            }
            if !baseParts.isEmpty {
                baseParts.removeLast()
            }
            resolvedParts.append(contentsOf: baseParts)
        }

        for part in pathParts(decodedPath) {
            switch part {
            case ".":
                continue
            case "..":
                guard resolvedParts.count > rootDepth else {
                    return nil
                }
                resolvedParts.removeLast()
            default:
                resolvedParts.append(part)
            }
        }

        let normalized = resolvedParts.joined(separator: "/")
        if let fragment = components.fragment, !fragment.isEmpty {
            return normalized + "#" + fragment
        }
        return normalized
    }

    func readerURL(for href: String, bookId: UUID, relativeTo basePath: String? = nil) -> URL? {
        guard let path = normalizedResourcePath(href, relativeTo: basePath) else {
            return nil
        }
        return URL(string: "readerflow://book/\(bookId.uuidString)/\(path)")
    }

    private func pathParts(_ path: String) -> [String] {
        path.split(separator: "/")
            .map(String.init)
            .filter { !$0.isEmpty }
    }
}
