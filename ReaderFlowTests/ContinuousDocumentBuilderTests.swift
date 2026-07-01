@testable import ReaderFlow
import Testing

struct ContinuousDocumentBuilderTests {
    @Test func buildsSanitizedContinuousDocument() {
        let builder = ContinuousDocumentBuilder(
            sanitizer: EPUBContentSanitizer(),
            resolver: EPUBResourceResolver(packageRoot: "OPS")
        )
        let settings = ReaderSettingsEntity()

        let html = builder.buildDocument(
            title: "Book",
            chapters: [
                ContinuousDocumentChapter(
                    href: "chapter1.xhtml",
                    title: "Chapter 1",
                    bodyHTML: #"<h1 onclick="bad()">Chapter</h1><script>alert(1)</script><p>Text</p>"#
                ),
            ],
            settings: settings,
            bridgeToken: "token"
        )

        #expect(html.contains("data-spine-index=\"0\""))
        #expect(html.contains("<p>Text</p>"))
        #expect(!html.localizedCaseInsensitiveContains("<script>alert"))
        #expect(!html.localizedCaseInsensitiveContains("onclick"))
        #expect(html.contains("window.__readerFlowBridgeToken"))
    }
}
