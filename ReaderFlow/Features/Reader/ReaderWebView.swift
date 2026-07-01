import SwiftUI
import WebKit

struct ReaderProgressMessage: Decodable, Hashable {
    var scrollY: Double
    var documentHeight: Double
    var viewportHeight: Double
    var totalProgression: Double
}

struct ReaderWebView: UIViewRepresentable {
    let html: String
    let expectedBridgeToken: String
    @Binding var speed: Double
    @Binding var isScrolling: Bool
    var onProgress: (ReaderProgressMessage) -> Void
    var onSelection: (ReaderSelectionPayload) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(expectedBridgeToken: expectedBridgeToken, onProgress: onProgress, onSelection: onSelection)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = false
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
        let command = """
        window.ReaderFlow && window.ReaderFlow.setSpeed(\(speed));
        window.ReaderFlow && window.ReaderFlow.\(isScrolling ? "start" : "pause")();
        """
        webView.evaluateJavaScript(command)
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        let expectedBridgeToken: String
        var onProgress: (ReaderProgressMessage) -> Void
        var onSelection: (ReaderSelectionPayload) -> Void

        init(
            expectedBridgeToken: String,
            onProgress: @escaping (ReaderProgressMessage) -> Void,
            onSelection: @escaping (ReaderSelectionPayload) -> Void
        ) {
            self.expectedBridgeToken = expectedBridgeToken
            self.onProgress = onProgress
            self.onSelection = onSelection
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
            case "progressChanged":
                decode(ReaderProgressMessage.self, from: body["payload"]).map(onProgress)
            case "selectionSaved":
                decode(ReaderSelectionPayload.self, from: body["payload"]).map(onSelection)
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
