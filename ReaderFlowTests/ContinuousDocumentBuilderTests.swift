import Foundation
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
            bridgeToken: "token",
            bookId: UUID(uuidString: "44444444-4444-4444-4444-444444444444"),
            bookFingerprint: "fingerprint",
            languageCode: "ar"
        )

        #expect(html.contains("<html lang=\"ar\" dir=\"auto\">"))
        #expect(html.contains("id=\"rf-spine-0\""))
        #expect(html.contains("class=\"rf-chapter\" dir=\"auto\""))
        #expect(html.contains("data-spine-index=\"0\""))
        #expect(html.contains("data-normalized-href=\"OPS/chapter1.xhtml\""))
        #expect(html.contains("<p>Text</p>"))
        #expect(!html.localizedCaseInsensitiveContains("<script>alert"))
        #expect(!html.localizedCaseInsensitiveContains("onclick"))
        #expect(html.contains("window.__readerFlowBridgeToken"))
        #expect(html.contains("window.__readerFlowBookId = \"44444444-4444-4444-4444-444444444444\""))
        #expect(html.contains("window.__readerFlowBookFingerprint = \"fingerprint\""))
    }

    @Test func emitsReaderSettingsCSSVariables() {
        let settings = ReaderDocumentSettings(
            textSize: 20,
            lineHeight: 1.7,
            marginScale: 1.25,
            theme: .dark,
            fontFamily: .systemSans
        )

        let css = settings.cssCustomProperties

        #expect(css.contains("--rf-bg: #121212;"))
        #expect(css.contains("--rf-font-family: -apple-system"))
        #expect(css.contains("--rf-text-size: 20.0px;"))
        #expect(css.contains("--rf-line-height: 1.7;"))
        #expect(css.contains("--rf-horizontal-padding: 28px;"))
    }

    @Test func normalizesLanguageMetadataForHTMLLangAttribute() {
        let builder = ContinuousDocumentBuilder(
            sanitizer: EPUBContentSanitizer(),
            resolver: EPUBResourceResolver(packageRoot: "OPS")
        )
        let settings = ReaderDocumentSettings()
        let chapters = [
            ContinuousDocumentChapter(
                href: "chapter1.xhtml",
                title: "Chapter 1",
                bodyHTML: "<p>Text</p>"
            ),
        ]

        let normalizedHTML = builder.buildDocument(
            title: "Book",
            chapters: chapters,
            settings: settings,
            bridgeToken: "token",
            languageCode: "pt_BR"
        )
        let unsafeHTML = builder.buildDocument(
            title: "Book",
            chapters: chapters,
            settings: settings,
            bridgeToken: "token",
            languageCode: #"en" onload="bad"#
        )

        #expect(ReaderHTMLLanguage.attributeValue(for: nil) == "und")
        #expect(ReaderHTMLLanguage.attributeValue(for: "  ") == "und")
        #expect(ReaderHTMLLanguage.attributeValue(for: "pt_BR") == "pt-BR")
        #expect(ReaderHTMLLanguage.attributeValue(for: #"en" onload="bad"#) == "und")
        #expect(normalizedHTML.contains(#"<html lang="pt-BR" dir="auto">"#))
        #expect(unsafeHTML.contains(#"<html lang="und" dir="auto">"#))
    }
}
