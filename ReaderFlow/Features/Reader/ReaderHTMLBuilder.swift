import Foundation

enum ReaderHTMLBuilder {
    static func placeholderHTML(book: BookEntity, settings: ReaderSettingsEntity, bridgeToken: String) -> String {
        let escapedTitle = book.title.htmlEscaped
        let documentSettings = ReaderDocumentSettings(settings)
        let escapedBridgeToken = bridgeToken.htmlEscaped
        return """
        <!doctype html>
        <html>
        <head>
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <style>
            \(ReaderWebAssets.css)
            \(documentSettings.cssCustomProperties)
          </style>
        </head>
        <body>
          <main id="book">
            <section class="rf-chapter" data-spine-index="0" data-href="placeholder.xhtml" data-title="Imported Book">
              <h1>\(escapedTitle)</h1>
              <p>This EPUB has been imported. The next implementation stage replaces this placeholder with sanitized EPUB chapter content from the continuous document builder.</p>
              <p>Select text here to exercise the excerpt bridge while the full EPUB renderer is being connected.</p>
              <p>ReaderFlow keeps the reading surface full screen, scrolls vertically, and saves excerpts with location context.</p>
              \(Array(repeating: "<p>Autoscroll proof text for the reader surface. This paragraph gives the renderer enough height to exercise smooth scrolling and pause behavior.</p>", count: 40).joined())
            </section>
          </main>
          <script>
            window.__readerFlowBridgeToken = "\(escapedBridgeToken)";
          </script>
          <script>
            \(ReaderWebAssets.javascript)
          </script>
        </body>
        </html>
        """
    }
}

enum ReaderWebAssets {
    static let css = """
    html, body {
      margin: 0;
      padding: 0;
      background: var(--rf-bg, #fbfaf7);
      color: var(--rf-text, #171717);
      font-family: var(--rf-font-family, ui-serif, Georgia, serif);
      font-size: var(--rf-text-size, 18px);
      line-height: var(--rf-line-height, 1.55);
    }
    body {
      padding: 18vh var(--rf-horizontal-padding, 22px) 32vh;
    }
    main {
      max-width: 42rem;
      margin: 0 auto;
    }
    h1 {
      font-size: 1.45rem;
      line-height: 1.2;
      margin: 0 0 1.5rem;
    }
    p {
      margin: 0 0 1.05rem;
    }
    .rf-highlight {
      background: var(--rf-selection, rgba(255, 214, 94, 0.58));
      border-radius: 3px;
    }
    """

    static let javascript = """
    (() => {
      const post = (type, payload = {}) => {
        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.readerFlow) {
          window.webkit.messageHandlers.readerFlow.postMessage({
            type,
            token: window.__readerFlowBridgeToken || '',
            payload
          });
        }
      };

      let speed = 25;
      let running = false;
      let lastTime = null;
      let lastProgressPost = 0;

      const progress = () => {
        const documentHeight = Math.max(document.documentElement.scrollHeight, document.body.scrollHeight);
        const viewportHeight = window.innerHeight || 1;
        const maxScroll = Math.max(1, documentHeight - viewportHeight);
        return {
          scrollY: window.scrollY,
          documentHeight,
          viewportHeight,
          totalProgression: Math.max(0, Math.min(1, window.scrollY / maxScroll))
        };
      };

      const tick = (time) => {
        if (!running) {
          lastTime = null;
          return;
        }
        if (lastTime === null) {
          lastTime = time;
        }
        const delta = Math.max(0, (time - lastTime) / 1000);
        lastTime = time;
        window.scrollBy(0, speed * delta);
        if (time - lastProgressPost > 1000) {
          lastProgressPost = time;
          post('progressChanged', progress());
        }
        const current = progress();
        if (current.totalProgression >= 1) {
          running = false;
          post('scrollStateChanged', { running: false });
          return;
        }
        requestAnimationFrame(tick);
      };

      const selectionPayload = () => {
        const selection = window.getSelection();
        if (!selection || selection.isCollapsed || selection.rangeCount === 0) {
          return null;
        }
        const text = selection.toString().trim();
        if (text.length < 2) {
          return null;
        }
        const id = crypto.randomUUID();
        const current = progress();
        return {
          highlightId: id,
          selectedText: text,
          contextBefore: '',
          contextAfter: '',
          locator: {
            bookId: '00000000-0000-0000-0000-000000000000',
            bookFingerprint: '',
            spineIndex: 0,
            href: 'placeholder.xhtml',
            chapterTitle: 'Imported Book',
            chapterProgression: current.totalProgression,
            totalProgression: current.totalProgression,
            scrollY: current.scrollY,
            documentHeight: current.documentHeight,
            textQuote: { exact: text, prefix: '', suffix: '', normalizedStartOffset: null, normalizedEndOffset: null },
            domTextPath: null,
            contentHash: null,
            readiumLocatorJSON: null,
            createdAt: new Date().toISOString().replace(/\\.\\d{3}Z$/, 'Z')
          }
        };
      };

      document.addEventListener('selectionchange', () => {
        clearTimeout(window.__readerFlowSelectionTimer);
        window.__readerFlowSelectionTimer = setTimeout(() => {
          const payload = selectionPayload();
          if (!payload) return;
          post('selectionSaved', payload);
          window.getSelection().removeAllRanges();
        }, 650);
      });

      window.ReaderFlow = {
        setSpeed(value) {
          speed = Number(value) || 25;
        },
        start() {
          if (!running) {
            running = true;
            requestAnimationFrame(tick);
            post('scrollStateChanged', { running: true });
          }
        },
        pause() {
          running = false;
          post('progressChanged', progress());
          post('scrollStateChanged', { running: false });
        }
      };

      post('readerReady', progress());
    })();
    """
}
