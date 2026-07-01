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
            \(settings.cssCustomProperties)
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
    var marginScale: Double
    var theme: ReaderTheme
    var fontFamily: ReaderFontFamily

    init(
        textSize: Double = 18,
        lineHeight: Double = 1.55,
        marginScale: Double = 1,
        theme: ReaderTheme = .system,
        fontFamily: ReaderFontFamily = .systemSerif
    ) {
        self.textSize = textSize
        self.lineHeight = lineHeight
        self.marginScale = marginScale
        self.theme = theme
        self.fontFamily = fontFamily
    }

    init(_ settings: ReaderSettingsEntity) {
        textSize = settings.textSize
        lineHeight = settings.lineHeight
        marginScale = settings.marginScale
        theme = ReaderTheme(rawValue: settings.theme) ?? .system
        fontFamily = ReaderFontFamily(rawValue: settings.fontFamily) ?? .systemSerif
    }

    var cssCustomProperties: String {
        switch theme {
        case .system:
            """
            :root {
              \(baseCSSVariables(colors: .light))
            }
            @media (prefers-color-scheme: dark) {
              :root {
                \(baseCSSVariables(colors: .dark))
              }
            }
            """
        case .light:
            """
            :root {
              \(baseCSSVariables(colors: .light))
            }
            """
        case .dark:
            """
            :root {
              \(baseCSSVariables(colors: .dark))
            }
            """
        }
    }

    private func baseCSSVariables(colors: ReaderDocumentColors) -> String {
        """
        --rf-bg: \(colors.background);
        --rf-text: \(colors.text);
        --rf-muted-text: \(colors.mutedText);
        --rf-selection: \(colors.selection);
        --rf-font-family: \(fontFamily.cssFontStack);
        --rf-text-size: \(clamped(textSize, min: 14, max: 34))px;
        --rf-line-height: \(clamped(lineHeight, min: 1.15, max: 2.2));
        --rf-horizontal-padding: \(Int((22 * clamped(marginScale, min: 0.75, max: 1.6)).rounded()))px;
        """
    }

    private func clamped(_ value: Double, min minValue: Double, max maxValue: Double) -> Double {
        min(max(value, minValue), maxValue)
    }
}

private struct ReaderDocumentColors: Hashable {
    var background: String
    var text: String
    var mutedText: String
    var selection: String

    static let light = ReaderDocumentColors(
        background: "#fbfaf7",
        text: "#171717",
        mutedText: "#5f5a52",
        selection: "rgba(255, 214, 94, 0.58)"
    )

    static let dark = ReaderDocumentColors(
        background: "#121212",
        text: "#f1eee8",
        mutedText: "#b8b1a7",
        selection: "rgba(255, 202, 80, 0.42)"
    )
}

private extension ReaderFontFamily {
    var cssFontStack: String {
        switch self {
        case .systemSerif:
            "ui-serif, Georgia, \"Times New Roman\", serif"
        case .systemSans:
            "-apple-system, BlinkMacSystemFont, \"SF Pro Text\", \"Helvetica Neue\", sans-serif"
        case .atkinsonHyperlegible:
            "\"Atkinson Hyperlegible\", \"Avenir Next\", -apple-system, BlinkMacSystemFont, sans-serif"
        case .literata:
            "\"Literata\", Charter, Georgia, \"Times New Roman\", serif"
        case .sourceSerif4:
            "\"Source Serif 4\", Charter, Georgia, \"Times New Roman\", serif"
        }
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
