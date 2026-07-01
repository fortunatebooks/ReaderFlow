import Foundation
@testable import ReaderFlow
import Testing

struct EPUBResourceResolverTests {
    @Test func normalizesSafeRelativePaths() throws {
        let resolver = EPUBResourceResolver(packageRoot: "OPS")

        let path = try #require(resolver.normalizedResourcePath("images/cover.jpg", relativeTo: "chapter1.xhtml"))

        #expect(path == "OPS/images/cover.jpg")
    }

    @Test func rejectsTraversalOutsidePackage() {
        let resolver = EPUBResourceResolver(packageRoot: "OPS")

        #expect(resolver.normalizedResourcePath("../../secret.txt", relativeTo: "chapter1.xhtml") == nil)
        #expect(resolver.normalizedResourcePath("../secret.txt", relativeTo: "chapter1.xhtml") == nil)
        #expect(resolver.normalizedResourcePath("%2e%2e/secret.txt", relativeTo: "chapter1.xhtml") == nil)
    }

    @Test func resolvesNestedBasePathsInsidePackageRoot() throws {
        let resolver = EPUBResourceResolver(packageRoot: "OPS")

        let path = try #require(resolver.normalizedResourcePath("../images/cover.jpg", relativeTo: "Text/chapter1.xhtml"))

        #expect(path == "OPS/images/cover.jpg")
    }

    @Test func doesNotDuplicatePackageRootWhenBasePathIncludesIt() throws {
        let resolver = EPUBResourceResolver(packageRoot: "OPS")

        let path = try #require(resolver.normalizedResourcePath("../images/cover.jpg", relativeTo: "OPS/Text/chapter1.xhtml"))

        #expect(path == "OPS/images/cover.jpg")
    }

    @Test func preservesFragments() throws {
        let resolver = EPUBResourceResolver(packageRoot: "OPS")

        let path = try #require(resolver.normalizedResourcePath("chapter2.xhtml#note", relativeTo: "chapter1.xhtml"))

        #expect(path == "OPS/chapter2.xhtml#note")
    }
}

struct EPUBPackageParserTests {
    @Test func parsesContainerRootfilePath() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <rootfiles>
            <rootfile full-path="OPS/content.opf" media-type="application/oebps-package+xml"/>
          </rootfiles>
        </container>
        """

        let container = try EPUBPackageParser().parseContainerXML(Data(xml.utf8))

        #expect(container.rootfilePath == "OPS/content.opf")
    }

    @Test func parsesPackageMetadataManifestAndSpine() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <package version="3.0" unique-identifier="book-id" xmlns="http://www.idpf.org/2007/opf">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:title>Test Book</dc:title>
            <dc:creator>Example Author</dc:creator>
            <dc:language>en</dc:language>
            <dc:identifier id="other-id">ignored</dc:identifier>
            <dc:identifier id="book-id">urn:uuid:test-book</dc:identifier>
            <meta property="dcterms:modified">2026-01-01T00:00:00Z</meta>
          </metadata>
          <manifest>
            <item id="chapter-1" href="Text/chapter1.xhtml" media-type="application/xhtml+xml"/>
            <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
            <item id="style" href="Styles/book.css" media-type="text/css"/>
          </manifest>
          <spine>
            <itemref idref="chapter-1"/>
            <itemref idref="nav" linear="no"/>
          </spine>
        </package>
        """

        let package = try EPUBPackageParser().parsePackageXML(Data(xml.utf8), packagePath: "OPS/content.opf")

        #expect(package.opfPath == "OPS/content.opf")
        #expect(package.packageRoot == "OPS")
        #expect(package.metadata.title == "Test Book")
        #expect(package.metadata.creators == ["Example Author"])
        #expect(package.metadata.language == "en")
        #expect(package.metadata.identifier == "urn:uuid:test-book")
        #expect(package.metadata.modified == "2026-01-01T00:00:00Z")
        #expect(package.manifest.count == 3)
        #expect(package.manifestItem(id: "nav")?.properties == ["nav"])
        #expect(package.spine == [
            EPUBSpineItem(idref: "chapter-1", linear: true),
            EPUBSpineItem(idref: "nav", linear: false),
        ])
        #expect(package.readingOrder.map(\.href) == ["Text/chapter1.xhtml", "nav.xhtml"])
        #expect(package.readingOrder.map(\.linear) == [true, false])
    }

    @Test func readsExpandedEPUBDirectory() throws {
        let parser = EPUBPackageParser()
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory
            .appendingPathComponent("ReaderFlowParserTests")
            .appendingPathComponent(UUID().uuidString)

        defer {
            try? fileManager.removeItem(at: rootURL)
        }

        try fileManager.createDirectory(
            at: rootURL.appendingPathComponent("META-INF"),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: rootURL.appendingPathComponent("OEBPS"),
            withIntermediateDirectories: true
        )

        try write(
            """
            <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
              <rootfiles>
                <rootfile full-path="OEBPS/package.opf" media-type="application/oebps-package+xml"/>
              </rootfiles>
            </container>
            """,
            to: rootURL
                .appendingPathComponent("META-INF")
                .appendingPathComponent("container.xml")
        )
        try write(
            """
            <package version="3.0" xmlns="http://www.idpf.org/2007/opf">
              <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
                <dc:title>Expanded Book</dc:title>
              </metadata>
              <manifest>
                <item id="chapter" href="Text/chapter.xhtml" media-type="application/xhtml+xml"/>
              </manifest>
              <spine>
                <itemref idref="chapter"/>
              </spine>
            </package>
            """,
            to: rootURL
                .appendingPathComponent("OEBPS")
                .appendingPathComponent("package.opf")
        )

        let package = try parser.parseExpandedEPUB(at: rootURL)

        #expect(package.metadata.title == "Expanded Book")
        #expect(package.opfPath == "OEBPS/package.opf")
        #expect(package.packageRoot == "OEBPS")
        #expect(package.readingOrder.first?.href == "Text/chapter.xhtml")
        #expect(package.resourceResolver.normalizedResourcePath("Text/chapter.xhtml") == "OEBPS/Text/chapter.xhtml")
    }

    @Test func rejectsUnsafeContainerRootfilePath() throws {
        let xml = """
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <rootfiles>
            <rootfile full-path="../package.opf" media-type="application/oebps-package+xml"/>
          </rootfiles>
        </container>
        """

        do {
            _ = try EPUBPackageParser().parseContainerXML(Data(xml.utf8))
            Issue.record("Expected unsafe rootfile path to throw")
        } catch let EPUBParserError.unsafeRootfilePath(path) {
            #expect(path == "../package.opf")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    private func write(_ string: String, to url: URL) throws {
        try Data(string.utf8).write(to: url)
    }
}
