@testable import ReaderFlow
import Testing

struct EPUBContentSanitizerTests {
    @Test func removesScriptTagsAndInlineHandlers() {
        let html = #"<body onload="steal()"><script>alert(1)</script><p onclick="tap()">Text</p></body>"#

        let sanitized = EPUBContentSanitizer().sanitizeHTML(html)

        #expect(!sanitized.localizedCaseInsensitiveContains("<script"))
        #expect(!sanitized.localizedCaseInsensitiveContains("onload"))
        #expect(!sanitized.localizedCaseInsensitiveContains("onclick"))
        #expect(sanitized.contains("Text"))
    }

    @Test func removesDangerousURLsAndRemoteLoads() {
        let html = #"<a href="javascript:alert(1)">Bad</a><img src="https://example.com/a.png"><style>p{background:url("http://example.com/a.png")}</style>"#

        let sanitized = EPUBContentSanitizer().sanitizeHTML(html)

        #expect(!sanitized.localizedCaseInsensitiveContains("javascript:"))
        #expect(!sanitized.localizedCaseInsensitiveContains("https://example.com"))
        #expect(!sanitized.localizedCaseInsensitiveContains("http://example.com"))
    }
}
