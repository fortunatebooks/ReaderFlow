import Foundation

enum ReaderHTMLBuilder {
    static func placeholderHTML(book: BookEntity, settings: ReaderSettingsEntity, bridgeToken: String) -> String {
        let escapedTitle = book.title.htmlEscaped
        let documentSettings = ReaderDocumentSettings(settings)
        let escapedBridgeToken = bridgeToken.htmlEscaped
        return """
        <!doctype html>
        <html lang="\(ReaderHTMLLanguage.attributeValue(for: book.languageCode))" dir="auto">
        <head>
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <style>
            \(ReaderWebAssets.css)
            \(documentSettings.cssCustomProperties)
          </style>
        </head>
        <body>
          <main id="book">
            <section id="rf-spine-0" class="rf-chapter" dir="auto" data-spine-index="0" data-href="placeholder.xhtml" data-normalized-href="placeholder.xhtml" data-title="Imported Book">
              <h1>\(escapedTitle)</h1>
              <p>This EPUB has been imported. The next implementation stage replaces this placeholder with sanitized EPUB chapter content from the continuous document builder.</p>
              <p>Select text here to exercise the excerpt bridge while the full EPUB renderer is being connected.</p>
              <p>ReaderFlow keeps the reading surface full screen, scrolls vertically, and saves excerpts with location context.</p>
              \(Array(repeating: "<p>Autoscroll proof text for the reader surface. This paragraph gives the renderer enough height to exercise smooth scrolling and pause behavior.</p>", count: 40).joined())
            </section>
          </main>
          <script>
            window.__readerFlowBridgeToken = "\(escapedBridgeToken)";
            window.__readerFlowBookId = "\(book.id.uuidString)";
            window.__readerFlowBookFingerprint = "\(book.contentFingerprint.htmlEscaped)";
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
      let touchStart = null;
      let suppressClickUntil = 0;

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

      const wordsBefore = (text, count = 10) => text
        .trim()
        .split(/\\s+/)
        .filter(Boolean)
        .slice(-count)
        .join(' ');

      const wordsAfter = (text, count = 10) => text
        .trim()
        .split(/\\s+/)
        .filter(Boolean)
        .slice(0, count)
        .join(' ');

      const closestChapter = (node) => {
        let current = node;
        if (current && current.nodeType === Node.TEXT_NODE) {
          current = current.parentElement;
        }
        return (current && current.closest && current.closest('.rf-chapter')) || document.querySelector('.rf-chapter');
      };

      const selectionContext = (range, chapter) => {
        if (!chapter) {
          return { before: '', after: '' };
        }
        try {
          const beforeRange = document.createRange();
          beforeRange.selectNodeContents(chapter);
          beforeRange.setEnd(range.startContainer, range.startOffset);

          const afterRange = document.createRange();
          afterRange.selectNodeContents(chapter);
          afterRange.setStart(range.endContainer, range.endOffset);

          return {
            before: wordsBefore(beforeRange.toString()),
            after: wordsAfter(afterRange.toString())
          };
        } catch (_) {
          return { before: '', after: '' };
        }
      };

      const chapterProgression = (range, chapter) => {
        if (!chapter) {
          return progress().totalProgression;
        }
        const chapterRect = chapter.getBoundingClientRect();
        const rangeRect = range.getBoundingClientRect();
        const chapterTop = window.scrollY + chapterRect.top;
        const selectionTop = window.scrollY + (rangeRect.height > 0 ? rangeRect.top : chapterRect.top);
        const chapterHeight = Math.max(1, chapter.scrollHeight || chapterRect.height || 1);
        return Math.max(0, Math.min(1, (selectionTop - chapterTop) / chapterHeight));
      };

      const markSelection = (range, highlightId) => {
        try {
          const marker = document.createElement('mark');
          marker.className = 'rf-highlight';
          marker.dataset.highlightId = highlightId;
          range.surroundContents(marker);
          return true;
        } catch (_) {
          return false;
        }
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
        const range = selection.getRangeAt(0);
        const chapter = closestChapter(range.startContainer);
        const context = selectionContext(range, chapter);
        const spineIndex = Number(chapter && chapter.dataset ? chapter.dataset.spineIndex : 0) || 0;
        const href = (chapter && chapter.dataset && chapter.dataset.href) || '';
        const chapterTitle = (chapter && chapter.dataset && chapter.dataset.title) || null;
        return {
          highlightId: id,
          selectedText: text,
          contextBefore: context.before,
          contextAfter: context.after,
          locator: {
            bookId: window.__readerFlowBookId || '00000000-0000-0000-0000-000000000000',
            bookFingerprint: window.__readerFlowBookFingerprint || '',
            spineIndex,
            href,
            chapterTitle,
            chapterProgression: chapterProgression(range, chapter),
            totalProgression: current.totalProgression,
            scrollY: current.scrollY,
            documentHeight: current.documentHeight,
            textQuote: { exact: text, prefix: context.before, suffix: context.after, normalizedStartOffset: null, normalizedEndOffset: null },
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
          const selection = window.getSelection();
          if (selection && selection.rangeCount > 0) {
            markSelection(selection.getRangeAt(0).cloneRange(), payload.highlightId);
          }
          post('selectionSaved', payload);
          window.getSelection().removeAllRanges();
        }, 650);
      });

      document.addEventListener('click', (event) => {
        if (Date.now() < suppressClickUntil) {
          return;
        }
        if (event.target && event.target.closest && event.target.closest('a')) {
          return;
        }
        const selection = window.getSelection();
        if (selection && !selection.isCollapsed) {
          return;
        }
        post('readerTapped', {});
      });

      document.addEventListener('touchstart', (event) => {
        if (event.touches.length !== 1) {
          touchStart = null;
          return;
        }
        const touch = event.touches[0];
        touchStart = { x: touch.clientX, y: touch.clientY };
      }, { passive: true });

      document.addEventListener('touchend', (event) => {
        if (!touchStart || event.changedTouches.length !== 1) {
          touchStart = null;
          return;
        }
        const selection = window.getSelection();
        if (selection && !selection.isCollapsed) {
          touchStart = null;
          return;
        }

        const touch = event.changedTouches[0];
        const dx = touch.clientX - touchStart.x;
        const dy = touch.clientY - touchStart.y;
        touchStart = null;

        if (Math.abs(dy) < 52 || Math.abs(dy) < Math.abs(dx) * 1.5) {
          return;
        }

        event.preventDefault();
        suppressClickUntil = Date.now() + 450;
        post('speedAdjustment', { delta: dy < 0 ? 5 : -5 });
      }, { passive: false });

      window.ReaderFlow = {
        setSpeed(value) {
          speed = Number(value) || 25;
        },
        scrollToProgress(value) {
          const documentHeight = Math.max(document.documentElement.scrollHeight, document.body.scrollHeight);
          const viewportHeight = window.innerHeight || 1;
          const maxScroll = Math.max(0, documentHeight - viewportHeight);
          const target = Math.max(0, Math.min(1, Number(value) || 0));
          window.scrollTo(0, maxScroll * target);
          post('progressChanged', progress());
        },
        scrollToHref(value) {
          const href = String(value || '').split('#')[0];
          if (!href) {
            return;
          }
          const chapters = Array.from(document.querySelectorAll('.rf-chapter'));
          const target = chapters.find((chapter) => chapter.dataset.normalizedHref === href || chapter.dataset.href === href);
          if (!target) {
            return;
          }
          target.scrollIntoView({ block: 'start' });
          post('progressChanged', progress());
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
