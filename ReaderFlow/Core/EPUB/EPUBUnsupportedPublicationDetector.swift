import Foundation

enum EPUBUnsupportedPublicationDetector {
    static func hasProtectedResources(in expandedRootURL: URL) -> Bool {
        let encryptionURL = expandedRootURL
            .appending(path: "META-INF", directoryHint: .isDirectory)
            .appending(path: "encryption.xml", directoryHint: .notDirectory)
        guard FileManager.default.fileExists(atPath: encryptionURL.path) else {
            return false
        }
        guard let data = try? Data(contentsOf: encryptionURL) else {
            return true
        }
        return hasProtectedEncryptionMetadata(data)
    }

    static func hasProtectedEncryptionMetadata(_ data: Data) -> Bool {
        let parser = XMLParser(data: data)
        let delegate = EncryptionXMLParserDelegate()
        parser.delegate = delegate
        parser.shouldProcessNamespaces = true
        parser.shouldResolveExternalEntities = false

        guard parser.parse() else {
            return true
        }
        return delegate.encryptedDataCount != delegate.algorithms.count ||
            delegate.algorithms.contains { !isFontObfuscationAlgorithm($0) }
    }

    static func hasAppleFixedLayoutDisplayOptions(in expandedRootURL: URL) -> Bool {
        let displayOptionsURL = expandedRootURL
            .appending(path: "META-INF", directoryHint: .isDirectory)
            .appending(path: "com.apple.ibooks.display-options.xml", directoryHint: .notDirectory)
        guard FileManager.default.fileExists(atPath: displayOptionsURL.path),
              let data = try? Data(contentsOf: displayOptionsURL)
        else {
            return false
        }
        return hasAppleFixedLayoutDisplayOptions(data)
    }

    static func hasAppleFixedLayoutDisplayOptions(_ data: Data) -> Bool {
        let parser = XMLParser(data: data)
        let delegate = AppleDisplayOptionsXMLParserDelegate()
        parser.delegate = delegate
        parser.shouldProcessNamespaces = true
        parser.shouldResolveExternalEntities = false

        guard parser.parse() else {
            return false
        }
        return delegate.hasFixedLayoutOption
    }

    private static func isFontObfuscationAlgorithm(_ value: String) -> Bool {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "http://www.idpf.org/2008/embedding" ||
            normalized == "http://ns.adobe.com/pdf/enc#rc"
    }
}

private final class EncryptionXMLParserDelegate: NSObject, XMLParserDelegate {
    private(set) var algorithms: [String] = []
    private(set) var encryptedDataCount = 0

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String]
    ) {
        let elementName = unsupportedMetadataElementName(elementName, qName: qName)
        if elementName == "EncryptedData" {
            encryptedDataCount += 1
            return
        }
        guard elementName == "EncryptionMethod" else {
            return
        }
        guard let algorithm = attributeDict["Algorithm"],
              !algorithm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            algorithms.append("")
            return
        }
        algorithms.append(algorithm)
    }
}

private final class AppleDisplayOptionsXMLParserDelegate: NSObject, XMLParserDelegate {
    private(set) var hasFixedLayoutOption = false
    private var currentOptionName: String?
    private var currentOptionText = ""

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String]
    ) {
        guard unsupportedMetadataElementName(elementName, qName: qName) == "option" else {
            return
        }
        currentOptionName = attributeDict["name"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        currentOptionText = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard currentOptionName != nil else {
            return
        }
        currentOptionText += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        guard unsupportedMetadataElementName(elementName, qName: qName) == "option",
              currentOptionName == "fixed-layout"
        else {
            currentOptionName = nil
            currentOptionText = ""
            return
        }

        let value = currentOptionText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if ["true", "yes", "1"].contains(value) {
            hasFixedLayoutOption = true
        }
        currentOptionName = nil
        currentOptionText = ""
    }
}

private func unsupportedMetadataElementName(_ elementName: String, qName: String?) -> String {
    let name = qName?.isEmpty == false ? qName ?? elementName : elementName
    return name.split(separator: ":").last.map(String.init) ?? name
}
