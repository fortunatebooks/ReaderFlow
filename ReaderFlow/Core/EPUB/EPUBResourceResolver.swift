import Foundation

struct EPUBResourceResolver {
    let packageRoot: String

    func normalizedResourcePath(_ href: String, relativeTo basePath: String? = nil) -> String? {
        guard let components = URLComponents(string: href), components.scheme == nil else {
            return nil
        }

        let encodedPath = components.percentEncodedPath
        guard !encodedPath.hasPrefix("/")
        else {
            return nil
        }

        let rootParts = pathParts(packageRoot)
        if encodedPath.isEmpty {
            guard let basePath,
                  let baseParts = normalizedBaseResourceParts(basePath, rootParts: rootParts),
                  !baseParts.isEmpty,
                  components.fragment?.isEmpty == false
            else {
                return nil
            }

            return appendingFragment(components.fragment, to: baseParts.joined(separator: "/"))
        }

        var resolvedParts = rootParts

        if let basePath {
            guard var baseParts = normalizedBaseResourceParts(basePath, rootParts: rootParts) else {
                return nil
            }
            if !baseParts.isEmpty {
                baseParts.removeLast()
            }
            resolvedParts = baseParts
        }
        let rootDepth = rootParts.count

        for part in pathParts(encodedPath) {
            guard let decodedPart = decodedSafePathSegment(part) else {
                return nil
            }
            switch decodedPart {
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
        return appendingFragment(components.fragment, to: normalized)
    }

    func readerURL(for href: String, bookId: UUID, relativeTo basePath: String? = nil) -> URL? {
        guard let path = normalizedResourcePath(href, relativeTo: basePath) else {
            return nil
        }
        return readerURL(forNormalizedResourcePath: path, bookId: bookId)
    }

    static func fileURL(forNormalizedResourcePath normalizedPath: String, rootURL: URL) -> URL? {
        let resourcePath = normalizedPath
            .split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map(String.init) ?? normalizedPath
        let root = rootURL.standardizedFileURL
        let components = resourcePath.split(separator: "/").map(String.init)
        guard !components.isEmpty else {
            return nil
        }
        var candidate = root

        for component in components {
            guard let decodedComponent = decodedSafePathSegment(component),
                  decodedComponent != ".",
                  decodedComponent != ".."
            else {
                return nil
            }
            candidate.appendPathComponent(decodedComponent)
        }
        candidate = candidate.standardizedFileURL

        guard candidate.path == root.path || candidate.path.hasPrefix(root.path + "/") else {
            return nil
        }
        return candidate
    }

    func readerURL(forNormalizedResourcePath normalizedPath: String, bookId: UUID) -> URL? {
        let parts = normalizedPath.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        let resourcePath = parts.first.map(String.init) ?? normalizedPath
        let fragment = parts.count > 1 ? String(parts[1]) : nil
        let resourceParts = pathParts(resourcePath)
        guard !resourceParts.isEmpty else {
            return nil
        }

        var components = URLComponents()
        components.scheme = "readerflow"
        components.host = "book"
        components.percentEncodedPath = "/" + ([bookId.uuidString] + resourceParts).joined(separator: "/")
        components.fragment = fragment?.isEmpty == false ? fragment : nil
        return components.url
    }

    private func pathParts(_ path: String) -> [String] {
        path.split(separator: "/")
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private func normalizedBaseResourceParts(_ basePath: String, rootParts: [String]) -> [String]? {
        guard let components = URLComponents(string: basePath),
              components.scheme == nil,
              !components.percentEncodedPath.hasPrefix("/")
        else {
            return nil
        }

        var parts: [String] = []
        for part in pathParts(components.percentEncodedPath) {
            guard let decodedPart = decodedSafePathSegment(part) else {
                return nil
            }
            switch decodedPart {
            case ".":
                continue
            case "..":
                return nil
            default:
                parts.append(part)
            }
        }

        if parts.starts(with: rootParts) {
            return parts
        }
        return rootParts + parts
    }

    private func appendingFragment(_ fragment: String?, to normalizedPath: String) -> String {
        guard let fragment, !fragment.isEmpty else {
            return normalizedPath
        }
        return normalizedPath + "#" + fragment
    }

    private static func decodedSafePathSegment(_ encodedPart: String) -> String? {
        guard let decodedPart = encodedPart.removingPercentEncoding,
              !decodedPart.isEmpty,
              !decodedPart.contains("/"),
              !decodedPart.contains("\\"),
              !decodedPart.contains("\0")
        else {
            return nil
        }
        return decodedPart
    }

    private func decodedSafePathSegment(_ encodedPart: String) -> String? {
        Self.decodedSafePathSegment(encodedPart)
    }
}
