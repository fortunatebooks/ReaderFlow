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

    @Test func resolvesFragmentOnlyHrefsAgainstBaseResource() throws {
        let resolver = EPUBResourceResolver(packageRoot: "OPS")

        let path = try #require(resolver.normalizedResourcePath("#note", relativeTo: "Text/chapter1.xhtml"))

        #expect(path == "OPS/Text/chapter1.xhtml#note")
    }

    @Test func readerURLsPercentEncodeResourcePaths() throws {
        let resolver = EPUBResourceResolver(packageRoot: "OPS")
        let bookId = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))

        let url = try #require(resolver.readerURL(for: "../Images/cover art.jpg", bookId: bookId, relativeTo: "Text/chapter1.xhtml"))

        #expect(url.absoluteString == "readerflow://book/11111111-1111-1111-1111-111111111111/OPS/Images/cover%20art.jpg")
    }

    @Test func preservesPercentEncodedHashInResourcePath() throws {
        let resolver = EPUBResourceResolver(packageRoot: "OPS")
        let bookId = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))

        let path = try #require(resolver.normalizedResourcePath("../Images/cover%231.jpg", relativeTo: "Text/chapter1.xhtml"))
        let url = try #require(resolver.readerURL(forNormalizedResourcePath: path, bookId: bookId))

        #expect(path == "OPS/Images/cover%231.jpg")
        #expect(url.absoluteString == "readerflow://book/11111111-1111-1111-1111-111111111111/OPS/Images/cover%231.jpg")
    }
}

struct EPUBContentLoaderTests {
    @Test func loadsBodyHTMLAndRewritesLocalResources() throws {
        let fileManager = FileManager.default
        let rootURL = try temporaryExpandedRoot()
        defer {
            try? fileManager.removeItem(at: rootURL)
        }

        try write(
            """
            <?xml version="1.0" encoding="UTF-8"?>
            <html xmlns="http://www.w3.org/1999/xhtml">
              <head>
                <title>Chapter One</title>
              </head>
              <body>
                <h1>Heading Fallback</h1>
                <style>.cover { background: url('../Images/bg.jpg'); } .remote { background: url('https://example.com/bg.jpg'); }</style>
                <p style="background-image: url('../Images/bg.jpg')">First text.</p>
                <img src="../Images/cover art.jpg" srcset="../Images/cover-small.jpg 1x, ../Images/cover%20large.jpg 2x"/>
                <a href="chapter2.xhtml#next">Next</a>
                <a href="chapter2.xhtml">Next chapter</a>
                <a href="#local-note">Local</a>
                <img src="../../secret.png"/>
                <img src="https://example.com/remote.png"/>
                <script>alert(1)</script>
              </body>
            </html>
            """,
            to: rootURL
                .appendingPathComponent("OEBPS")
                .appendingPathComponent("Text")
                .appendingPathComponent("chapter 1.xhtml")
        )
        try write(
            """
            <html xmlns="http://www.w3.org/1999/xhtml">
              <body>
                <h2>Second Chapter</h2>
                <p>Second text.</p>
              </body>
            </html>
            """,
            to: rootURL
                .appendingPathComponent("OEBPS")
                .appendingPathComponent("Text")
                .appendingPathComponent("chapter2.xhtml")
        )
        try write(
            """
            <html xmlns="http://www.w3.org/1999/xhtml">
              <body>
                <h2>Hash Chapter</h2>
                <p>Hash filename text.</p>
              </body>
            </html>
            """,
            to: rootURL
                .appendingPathComponent("OEBPS")
                .appendingPathComponent("Text")
                .appendingPathComponent("chapter#1.xhtml")
        )

        let bookId = try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
        let package = EPUBPackageDocument(
            opfPath: "OEBPS/content.opf",
            packageRoot: "OEBPS",
            metadata: .empty,
            manifest: [
                EPUBManifestItem(
                    id: "chapter-1",
                    href: "Text/chapter%201.xhtml",
                    mediaType: "application/xhtml+xml",
                    properties: []
                ),
                EPUBManifestItem(
                    id: "chapter-2",
                    href: "Text/chapter2.xhtml",
                    mediaType: "application/xhtml+xml",
                    properties: []
                ),
                EPUBManifestItem(
                    id: "chapter-hash",
                    href: "Text/chapter%231.xhtml",
                    mediaType: "application/xhtml+xml",
                    properties: []
                ),
                EPUBManifestItem(
                    id: "style",
                    href: "Styles/book.css",
                    mediaType: "text/css",
                    properties: []
                ),
            ],
            spine: [
                EPUBSpineItem(idref: "chapter-1", linear: true),
                EPUBSpineItem(idref: "style", linear: true),
                EPUBSpineItem(idref: "chapter-2", linear: true),
                EPUBSpineItem(idref: "chapter-hash", linear: true),
            ]
        )

        let chapters = try EPUBContentLoader().loadChapters(
            expandedRootURL: rootURL,
            package: package,
            bookId: bookId
        )

        #expect(chapters.map(\.href) == ["Text/chapter%201.xhtml", "Text/chapter2.xhtml", "Text/chapter%231.xhtml"])
        #expect(chapters.map(\.title) == ["Chapter One", "Second Chapter", "Hash Chapter"])
        #expect(chapters[0].bodyHTML.contains("First text."))
        #expect(!chapters[0].bodyHTML.contains("<title>"))
        #expect(chapters[0].bodyHTML.contains("src=\"readerflow://book/22222222-2222-2222-2222-222222222222/OEBPS/Images/cover%20art.jpg\""))
        #expect(chapters[0].bodyHTML.contains("readerflow://book/22222222-2222-2222-2222-222222222222/OEBPS/Images/cover-small.jpg 1x"))
        #expect(chapters[0].bodyHTML.contains("readerflow://book/22222222-2222-2222-2222-222222222222/OEBPS/Images/cover%20large.jpg 2x"))
        #expect(chapters[0].bodyHTML.contains("href=\"#next\""))
        #expect(chapters[0].bodyHTML.contains("href=\"#rf-spine-1\""))
        #expect(chapters[0].bodyHTML.contains("href=\"#local-note\""))
        #expect(chapters[0].bodyHTML.contains("readerflow://book/22222222-2222-2222-2222-222222222222/OEBPS/Images/bg.jpg"))
        #expect(!chapters[0].bodyHTML.localizedCaseInsensitiveContains("<script"))
        #expect(!chapters[0].bodyHTML.contains("https://example.com"))
        #expect(!chapters[0].bodyHTML.contains("../../secret.png"))
    }

    @Test func rejectsUnsafeReadingOrderHref() throws {
        let rootURL = try temporaryExpandedRoot()
        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }

        let bookId = try #require(UUID(uuidString: "33333333-3333-3333-3333-333333333333"))
        let package = EPUBPackageDocument(
            opfPath: "OEBPS/content.opf",
            packageRoot: "OEBPS",
            metadata: .empty,
            manifest: [
                EPUBManifestItem(
                    id: "chapter",
                    href: "../outside.xhtml",
                    mediaType: "application/xhtml+xml",
                    properties: []
                ),
            ],
            spine: [
                EPUBSpineItem(idref: "chapter", linear: true),
            ]
        )

        do {
            _ = try EPUBContentLoader().loadChapters(expandedRootURL: rootURL, package: package, bookId: bookId)
            Issue.record("Expected unsafe reading order href to throw")
        } catch let EPUBContentLoaderError.unsafeReadingOrderHref(href) {
            #expect(href == "../outside.xhtml")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    private func temporaryExpandedRoot() throws -> URL {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReaderFlowContentLoaderTests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        return rootURL
    }

    private func write(_ string: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(string.utf8).write(to: url)
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
