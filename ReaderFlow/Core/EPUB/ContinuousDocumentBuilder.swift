import Foundation

struct ContinuousDocumentBuilder {
    private let sanitizer: EPUBContentSanitizer
    private let resolver: EPUBResourceResolver

    init(sanitizer: EPUBContentSanitizer, resolver: EPUBResourceResolver) {
        self.sanitizer = sanitizer
        self.resolver = resolver
    }

    func buildDocument(
        title: String,
        chapters: [ContinuousDocumentChapter],
        settings: ReaderSettingsEntity,
        bridgeToken: String
    ) -> String {
        buildDocument(
            title: title,
            chapters: chapters,
            settings: ReaderDocumentSettings(settings),
            bridgeToken: bridgeToken
        )
    }

    func buildDocument(
        title: String,
        chapters: [ContinuousDocumentChapter],
        settings: ReaderDocumentSettings,
        bridgeToken: String
    ) -> String {
        let chapterHTML = chapters.enumerated()
            .map { index, chapter in
                sectionHTML(index: index, chapter: chapter)
            }
            .joined(separator: "\n")

        return """
        <!doctype html>
        <html>
        <head>
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <style>
            \(ReaderWebAssets.css)
            :root {
              --rf-text-size: \(settings.textSize)px;
              --rf-line-height: \(settings.lineHeight);
            }
          </style>
          <title>\(title.htmlEscaped)</title>
        </head>
        <body>
          <main id="book">
            \(chapterHTML)
          </main>
          <script>
            window.__readerFlowBridgeToken = "\(bridgeToken.htmlEscaped)";
          </script>
          <script>
            \(ReaderWebAssets.javascript)
          </script>
        </body>
        </html>
        """
    }

    private func sectionHTML(index: Int, chapter: ContinuousDocumentChapter) -> String {
        let sanitizedBody = sanitizer.sanitizeHTML(chapter.bodyHTML)
        let title = chapter.title.htmlEscaped
        let href = chapter.href.htmlEscaped
        return """
        <section class="rf-chapter" data-spine-index="\(index)" data-href="\(href)" data-title="\(title)">
          \(sanitizedBody)
        </section>
        """
    }
}

struct ContinuousDocumentChapter: Hashable {
    var href: String
    var title: String
    var bodyHTML: String
}

struct ReaderDocumentSettings: Hashable {
    var textSize: Double
    var lineHeight: Double

    init(textSize: Double = 18, lineHeight: Double = 1.55) {
        self.textSize = textSize
        self.lineHeight = lineHeight
    }

    init(_ settings: ReaderSettingsEntity) {
        textSize = settings.textSize
        lineHeight = settings.lineHeight
    }
}

extension String {
    var htmlEscaped: String {
        replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
