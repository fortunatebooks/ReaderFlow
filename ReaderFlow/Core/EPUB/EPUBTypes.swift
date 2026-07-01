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
    case duplicateImport
    case tooLarge
    case fixedLayoutUnsupported
    case protectedPublication

    var errorDescription: String? {
        switch self {
        case .securityScopeUnavailable:
            "ReaderFlow could not access this file."
        case .copyFailed:
            "ReaderFlow could not copy this EPUB."
        case .unsupported:
            "This file is not a supported EPUB."
        case .duplicateImport:
            "This EPUB is already in your ReaderFlow library."
        case .tooLarge:
            "This EPUB is too large for this version of ReaderFlow."
        case .fixedLayoutUnsupported:
            "Fixed-layout EPUBs are not supported in this version of ReaderFlow."
        case .protectedPublication:
            "ReaderFlow can import DRM-free EPUBs only."
        }
    }
}

enum EPUBParserError: LocalizedError {
    case missingContainer
    case unreadableContainer
    case unreadablePackage(path: String)
    case invalidXML(String)
    case missingRootfile
    case unsafeRootfilePath(String)

    var errorDescription: String? {
        switch self {
        case .missingContainer:
            "ReaderFlow could not find META-INF/container.xml."
        case .unreadableContainer:
            "ReaderFlow could not read META-INF/container.xml."
        case let .unreadablePackage(path):
            "ReaderFlow could not read the EPUB package document at \(path)."
        case let .invalidXML(detail):
            "ReaderFlow could not parse EPUB XML: \(detail)"
        case .missingRootfile:
            "ReaderFlow could not find an OPF rootfile in the EPUB container."
        case let .unsafeRootfilePath(path):
            "ReaderFlow rejected an unsafe OPF rootfile path: \(path)."
        }
    }
}

struct EPUBContainerDocument: Hashable {
    var rootfilePath: String
}

struct EPUBPackageDocument: Hashable {
    var opfPath: String
    var packageRoot: String
    var metadata: EPUBPackageMetadata
    var manifest: [EPUBManifestItem]
    var spine: [EPUBSpineItem]

    var resourceResolver: EPUBResourceResolver {
        EPUBResourceResolver(packageRoot: packageRoot)
    }

    var readingOrder: [EPUBReadingOrderItem] {
        spine.enumerated().compactMap { index, spineItem in
            guard let manifestItem = manifestItem(id: spineItem.idref) else {
                return nil
            }

            return EPUBReadingOrderItem(
                spineIndex: index,
                id: manifestItem.id,
                href: manifestItem.href,
                mediaType: manifestItem.mediaType,
                linear: spineItem.linear
            )
        }
    }

    func manifestItem(id: String) -> EPUBManifestItem? {
        manifest.first { $0.id == id }
    }

    var hasFixedLayoutContent: Bool {
        metadata.isFixedLayout || spine.contains(where: \.hasFixedLayoutProperty)
    }
}

struct EPUBPackageMetadata: Hashable {
    var title: String?
    var creators: [String]
    var language: String?
    var identifier: String?
    var modified: String?
    var coverItemID: String?
    var renditionLayout: String?

    static let empty = EPUBPackageMetadata(
        title: nil,
        creators: [],
        language: nil,
        identifier: nil,
        modified: nil,
        coverItemID: nil,
        renditionLayout: nil
    )

    var isFixedLayout: Bool {
        guard let renditionLayout else {
            return false
        }
        let normalized = renditionLayout
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return normalized == "pre-paginated" || normalized == "fixed"
    }
}

struct EPUBManifestItem: Hashable, Identifiable {
    var id: String
    var href: String
    var mediaType: String
    var properties: [String]
}

struct EPUBSpineItem: Hashable {
    var idref: String
    var linear: Bool
    var properties: [String] = []

    var hasFixedLayoutProperty: Bool {
        properties.contains { property in
            let normalized = property.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return normalized == "rendition:layout-pre-paginated" ||
                normalized == "rendition:layout-fixed"
        }
    }
}

struct EPUBReadingOrderItem: Hashable {
    var spineIndex: Int
    var id: String
    var href: String
    var mediaType: String
    var linear: Bool
}

struct EPUBPackageParser {
    func parseExpandedEPUB(at directoryURL: URL) throws -> EPUBPackageDocument {
        let containerURL = directoryURL
            .appendingPathComponent("META-INF")
            .appendingPathComponent("container.xml")

        guard FileManager.default.fileExists(atPath: containerURL.path) else {
            throw EPUBParserError.missingContainer
        }

        let containerData: Data
        do {
            containerData = try Data(contentsOf: containerURL)
        } catch {
            throw EPUBParserError.unreadableContainer
        }

        let container = try parseContainerXML(containerData)
        guard let packageURL = EPUBPath.url(forRelativePath: container.rootfilePath, relativeTo: directoryURL) else {
            throw EPUBParserError.unsafeRootfilePath(container.rootfilePath)
        }

        let packageData: Data
        do {
            packageData = try Data(contentsOf: packageURL)
        } catch {
            throw EPUBParserError.unreadablePackage(path: container.rootfilePath)
        }

        return try parsePackageXML(packageData, packagePath: container.rootfilePath)
    }

    func parseContainerXML(_ data: Data) throws -> EPUBContainerDocument {
        let delegate = EPUBContainerXMLParserDelegate()
        try parseXML(data, delegate: delegate)

        guard let rootfilePath = delegate.rootfilePath else {
            throw EPUBParserError.missingRootfile
        }

        guard let normalizedPath = EPUBPath.normalizedRelativePath(rootfilePath) else {
            throw EPUBParserError.unsafeRootfilePath(rootfilePath)
        }

        return EPUBContainerDocument(rootfilePath: normalizedPath)
    }

    func parsePackageXML(_ data: Data, packagePath: String) throws -> EPUBPackageDocument {
        let delegate = EPUBPackageXMLParserDelegate()
        try parseXML(data, delegate: delegate)

        let normalizedPath = EPUBPath.normalizedRelativePath(packagePath) ?? packagePath
        return EPUBPackageDocument(
            opfPath: normalizedPath,
            packageRoot: EPUBPath.parentDirectory(of: normalizedPath),
            metadata: delegate.metadata,
            manifest: delegate.manifest,
            spine: delegate.spine
        )
    }

    private func parseXML(_ data: Data, delegate: XMLParserDelegate) throws {
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = true
        parser.shouldResolveExternalEntities = false

        guard parser.parse() else {
            let message = parser.parserError?.localizedDescription ?? "Unknown parser error"
            throw EPUBParserError.invalidXML(message)
        }
    }
}

private enum EPUBPath {
    static func normalizedRelativePath(_ path: String) -> String? {
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty,
              !trimmedPath.hasPrefix("/"),
              URLComponents(string: trimmedPath)?.scheme == nil
        else {
            return nil
        }

        let decodedPath = trimmedPath.removingPercentEncoding ?? trimmedPath
        var parts: [String] = []
        for part in decodedPath.split(separator: "/", omittingEmptySubsequences: false).map(String.init) {
            switch part {
            case "", ".":
                continue
            case "..":
                return nil
            default:
                parts.append(part)
            }
        }

        guard !parts.isEmpty else {
            return nil
        }
        return parts.joined(separator: "/")
    }

    static func parentDirectory(of path: String) -> String {
        var parts = path.split(separator: "/").map(String.init)
        guard parts.count > 1 else {
            return ""
        }

        parts.removeLast()
        return parts.joined(separator: "/")
    }

    static func url(forRelativePath path: String, relativeTo rootURL: URL) -> URL? {
        guard let normalizedPath = normalizedRelativePath(path) else {
            return nil
        }

        return normalizedPath
            .split(separator: "/")
            .reduce(rootURL) { url, part in
                url.appendingPathComponent(String(part))
            }
    }
}

private final class EPUBContainerXMLParserDelegate: NSObject, XMLParserDelegate {
    private(set) var rootfilePath: String?
    private var fallbackRootfilePath: String?

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String]
    ) {
        guard normalizedElementName(elementName, qName: qName) == "rootfile",
              let fullPath = attributeDict["full-path"],
              !fullPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return
        }

        if fallbackRootfilePath == nil {
            fallbackRootfilePath = fullPath
        }

        if attributeDict["media-type"] == "application/oebps-package+xml" {
            rootfilePath = fullPath
        }
    }

    func parserDidEndDocument(_ parser: XMLParser) {
        if rootfilePath == nil {
            rootfilePath = fallbackRootfilePath
        }
    }
}

private final class EPUBPackageXMLParserDelegate: NSObject, XMLParserDelegate {
    private enum TextTarget {
        case title
        case creator
        case language
        case identifier
        case modified
        case renditionLayout
    }

    private(set) var metadata = EPUBPackageMetadata.empty
    private(set) var manifest: [EPUBManifestItem] = []
    private(set) var spine: [EPUBSpineItem] = []

    private var isInsideMetadata = false
    private var isInsideManifest = false
    private var isInsideSpine = false
    private var uniqueIdentifierID: String?
    private var currentIdentifierID: String?
    private var currentTextTarget: TextTarget?
    private var currentText = ""

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String]
    ) {
        let name = normalizedElementName(elementName, qName: qName)

        switch name {
        case "package":
            uniqueIdentifierID = attributeDict["unique-identifier"]
        case "metadata":
            isInsideMetadata = true
        case "manifest":
            isInsideManifest = true
        case "spine":
            isInsideSpine = true
        case "item" where isInsideManifest:
            parseManifestItem(attributes: attributeDict)
        case "itemref" where isInsideSpine:
            parseSpineItem(attributes: attributeDict)
        case "title" where isInsideMetadata:
            beginText(.title)
        case "creator" where isInsideMetadata:
            beginText(.creator)
        case "language" where isInsideMetadata:
            beginText(.language)
        case "identifier" where isInsideMetadata:
            currentIdentifierID = attributeDict["id"]
            beginText(.identifier)
        case "meta" where isInsideMetadata:
            parseMetadataMeta(attributes: attributeDict)
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard currentTextTarget != nil else {
            return
        }
        currentText += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let name = normalizedElementName(elementName, qName: qName)

        switch name {
        case "metadata":
            isInsideMetadata = false
        case "manifest":
            isInsideManifest = false
        case "spine":
            isInsideSpine = false
        case "title", "creator", "language", "identifier", "meta":
            commitTextIfNeeded()
        default:
            break
        }
    }

    private func parseManifestItem(attributes: [String: String]) {
        guard let id = attributes["id"],
              let href = attributes["href"],
              let mediaType = attributes["media-type"],
              !id.isEmpty,
              !href.isEmpty,
              !mediaType.isEmpty
        else {
            return
        }

        manifest.append(
            EPUBManifestItem(
                id: id,
                href: href,
                mediaType: mediaType,
                properties: attributes["properties"]?.split(whereSeparator: \.isWhitespace).map(String.init) ?? []
            )
        )
    }

    private func parseSpineItem(attributes: [String: String]) {
        guard let idref = attributes["idref"], !idref.isEmpty else {
            return
        }

        spine.append(
            EPUBSpineItem(
                idref: idref,
                linear: attributes["linear"]?.lowercased() != "no",
                properties: attributes["properties"]?.split(whereSeparator: \.isWhitespace).map(String.init) ?? []
            )
        )
    }

    private func parseMetadataMeta(attributes: [String: String]) {
        if attributes["property"] == "dcterms:modified" {
            beginText(.modified)
            return
        }

        if attributes["property"] == "rendition:layout" {
            beginText(.renditionLayout)
            return
        }

        if attributes["name"]?.lowercased() == "rendition:layout",
           let layout = attributes["content"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !layout.isEmpty
        {
            metadata.renditionLayout = layout
            return
        }

        if attributes["name"]?.lowercased() == "fixed-layout",
           let fixedLayout = attributes["content"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           ["true", "yes", "1"].contains(fixedLayout)
        {
            metadata.renditionLayout = "fixed"
            return
        }

        guard attributes["name"]?.lowercased() == "cover",
              let coverItemID = attributes["content"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !coverItemID.isEmpty
        else {
            return
        }
        metadata.coverItemID = coverItemID
    }

    private func beginText(_ target: TextTarget) {
        currentTextTarget = target
        currentText = ""
    }

    private func commitTextIfNeeded() {
        guard let target = currentTextTarget else {
            return
        }

        let value = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty {
            switch target {
            case .title:
                if metadata.title == nil {
                    metadata.title = value
                }
            case .creator:
                metadata.creators.append(value)
            case .language:
                if metadata.language == nil {
                    metadata.language = value
                }
            case .identifier:
                if metadata.identifier == nil || currentIdentifierID == uniqueIdentifierID {
                    metadata.identifier = value
                }
            case .modified:
                metadata.modified = value
            case .renditionLayout:
                if metadata.renditionLayout == nil {
                    metadata.renditionLayout = value
                }
            }
        }

        currentIdentifierID = nil
        currentTextTarget = nil
        currentText = ""
    }
}

private func normalizedElementName(_ elementName: String, qName: String?) -> String {
    let name = qName?.isEmpty == false ? qName ?? elementName : elementName
    return name.split(separator: ":").last.map(String.init) ?? name
}
