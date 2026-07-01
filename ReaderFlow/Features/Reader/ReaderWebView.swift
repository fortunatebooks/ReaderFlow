import Foundation
import SwiftUI
import WebKit

struct ReaderProgressMessage: Decodable, Hashable {
    var scrollY: Double
    var documentHeight: Double
    var viewportHeight: Double
    var totalProgression: Double
}

struct ReaderSpeedAdjustmentMessage: Decodable, Hashable {
    var delta: Double
}

struct ReaderScrollStateMessage: Decodable, Hashable {
    var running: Bool
    var reason: String?
}

struct ReaderNavigationRequest: Hashable {
    var id: UUID
    var href: String?
    var chapterProgression: Double?
    var fallbackProgress: Double?

    init(id: UUID, href: String?, chapterProgression: Double? = nil, fallbackProgress: Double? = nil) {
        self.id = id
        self.href = href
        self.chapterProgression = chapterProgression
        self.fallbackProgress = fallbackProgress
    }
}

struct ReaderWebView: UIViewRepresentable {
    let html: String
    let expectedBridgeToken: String
    let expectedBookId: UUID
    let bookResourceRootURL: URL?
    let initialProgress: Double
    let navigationRequest: ReaderNavigationRequest?
    @Binding var speed: Double
    @Binding var isScrolling: Bool
    var onProgress: (ReaderProgressMessage) -> Void
    var onSelection: (ReaderSelectionPayload) -> Void
    var onReady: () -> Void
    var onTap: () -> Void
    var onSpeedAdjustment: (Double) -> Void
    var onScrollStateChanged: (ReaderScrollStateMessage) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            expectedBridgeToken: expectedBridgeToken,
            currentHTML: html,
            currentInitialProgress: initialProgress,
            currentNavigationRequest: navigationRequest,
            currentSpeed: speed,
            currentIsScrolling: isScrolling,
            onProgress: onProgress,
            onSelection: onSelection,
            onReady: onReady,
            onTap: onTap,
            onSpeedAdjustment: onSpeedAdjustment,
            onScrollStateChanged: onScrollStateChanged
        )
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = false
        configuration.setURLSchemeHandler(
            ReaderResourceSchemeHandler(expectedBookId: expectedBookId, bookResourceRootURL: bookResourceRootURL),
            forURLScheme: "readerflow"
        )
        configuration.userContentController.add(context.coordinator, name: "readerFlow")

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.loadHTMLString(html, baseURL: nil)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.onProgress = onProgress
        context.coordinator.onSelection = onSelection
        context.coordinator.onReady = onReady
        context.coordinator.onTap = onTap
        context.coordinator.onSpeedAdjustment = onSpeedAdjustment
        context.coordinator.onScrollStateChanged = onScrollStateChanged
        context.coordinator.currentInitialProgress = initialProgress
        context.coordinator.currentNavigationRequest = navigationRequest
        context.coordinator.currentSpeed = speed
        context.coordinator.currentIsScrolling = isScrolling
        if context.coordinator.currentHTML != html {
            context.coordinator.currentHTML = html
            context.coordinator.isDocumentReady = false
            context.coordinator.hasAppliedInitialProgress = false
            webView.loadHTMLString(html, baseURL: nil)
            return
        }

        if context.coordinator.isDocumentReady {
            context.coordinator.applyNavigationIfNeeded(to: webView)
            context.coordinator.applyReaderState(to: webView)
        }
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        let expectedBridgeToken: String
        var currentHTML: String
        var currentInitialProgress: Double
        var currentNavigationRequest: ReaderNavigationRequest?
        var appliedNavigationRequestID: UUID?
        var currentSpeed: Double
        var currentIsScrolling: Bool
        var isDocumentReady = false
        var hasAppliedInitialProgress = false
        var onProgress: (ReaderProgressMessage) -> Void
        var onSelection: (ReaderSelectionPayload) -> Void
        var onReady: () -> Void
        var onTap: () -> Void
        var onSpeedAdjustment: (Double) -> Void
        var onScrollStateChanged: (ReaderScrollStateMessage) -> Void

        init(
            expectedBridgeToken: String,
            currentHTML: String,
            currentInitialProgress: Double,
            currentNavigationRequest: ReaderNavigationRequest?,
            currentSpeed: Double,
            currentIsScrolling: Bool,
            onProgress: @escaping (ReaderProgressMessage) -> Void,
            onSelection: @escaping (ReaderSelectionPayload) -> Void,
            onReady: @escaping () -> Void,
            onTap: @escaping () -> Void,
            onSpeedAdjustment: @escaping (Double) -> Void,
            onScrollStateChanged: @escaping (ReaderScrollStateMessage) -> Void
        ) {
            self.expectedBridgeToken = expectedBridgeToken
            self.currentHTML = currentHTML
            self.currentInitialProgress = currentInitialProgress
            self.currentNavigationRequest = currentNavigationRequest
            self.currentSpeed = currentSpeed
            self.currentIsScrolling = currentIsScrolling
            self.onProgress = onProgress
            self.onSelection = onSelection
            self.onReady = onReady
            self.onTap = onTap
            self.onSpeedAdjustment = onSpeedAdjustment
            self.onScrollStateChanged = onScrollStateChanged
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "readerFlow",
                  let body = message.body as? [String: Any],
                  let type = body["type"] as? String,
                  let token = body["token"] as? String,
                  token == expectedBridgeToken
            else {
                return
            }

            switch type {
            case "readerReady":
                onReady()
                decode(ReaderProgressMessage.self, from: body["payload"]).map(onProgress)
            case "progressChanged":
                decode(ReaderProgressMessage.self, from: body["payload"]).map(onProgress)
            case "selectionSaved":
                decode(ReaderSelectionPayload.self, from: body["payload"]).map(onSelection)
            case "readerTapped":
                onTap()
            case "speedAdjustment":
                decode(ReaderSpeedAdjustmentMessage.self, from: body["payload"]).map { onSpeedAdjustment($0.delta) }
            case "scrollStateChanged":
                decode(ReaderScrollStateMessage.self, from: body["payload"]).map(onScrollStateChanged)
            default:
                break
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }

            if url.scheme == "about" || url.scheme == "readerflow" {
                decisionHandler(.allow)
            } else {
                decisionHandler(.cancel)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isDocumentReady = true
            appliedNavigationRequestID = nil
            applyReaderState(to: webView)
            applyNavigationIfNeeded(to: webView)
        }

        func applyNavigationIfNeeded(to webView: WKWebView) {
            guard let request = currentNavigationRequest,
                  request.id != appliedNavigationRequestID
            else {
                return
            }
            appliedNavigationRequestID = request.id
            let hrefLiteral = javaScriptStringLiteral(request.href ?? "")
            let chapterProgression = javaScriptNumberLiteral(request.chapterProgression)
            let fallbackProgress = javaScriptNumberLiteral(request.fallbackProgress)
            webView.evaluateJavaScript(
                "window.ReaderFlow && window.ReaderFlow.scrollToLocator(\(hrefLiteral), \(chapterProgression), \(fallbackProgress));"
            )
        }

        func applyReaderState(to webView: WKWebView) {
            let initialProgressCommand: String
            if hasAppliedInitialProgress {
                initialProgressCommand = ""
            } else {
                hasAppliedInitialProgress = true
                initialProgressCommand = "window.ReaderFlow && window.ReaderFlow.scrollToProgress(\(boundedProgress(currentInitialProgress)));"
            }

            let command = """
            \(initialProgressCommand)
            window.ReaderFlow && window.ReaderFlow.setSpeed(\(currentSpeed));
            window.ReaderFlow && window.ReaderFlow.\(currentIsScrolling ? "start" : "pause")();
            """
            webView.evaluateJavaScript(command)
        }

        private func boundedProgress(_ value: Double) -> Double {
            min(1, max(0, value))
        }

        private func javaScriptStringLiteral(_ value: String) -> String {
            guard let data = try? JSONEncoder().encode(value),
                  let encoded = String(data: data, encoding: .utf8)
            else {
                return "\"\""
            }
            return encoded
        }

        private func javaScriptNumberLiteral(_ value: Double?) -> String {
            guard let value else {
                return "null"
            }
            return String(min(1, max(0, value)))
        }

        private func decode<T: Decodable>(_ type: T.Type, from object: Any?) -> T? {
            guard let object else { return nil }
            guard JSONSerialization.isValidJSONObject(object),
                  let data = try? JSONSerialization.data(withJSONObject: object)
            else {
                return nil
            }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try? decoder.decode(T.self, from: data)
        }
    }
}
