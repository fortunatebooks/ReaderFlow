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
    .rf-highlight-pulse {
      animation: readerflow-highlight-pulse 1.25s ease-out;
      outline: 2px solid rgba(255, 184, 28, 0.92);
      outline-offset: 2px;
    }
    @keyframes readerflow-highlight-pulse {
      0% { box-shadow: 0 0 0 0 rgba(255, 184, 28, 0.65); }
      100% { box-shadow: 0 0 0 12px rgba(255, 184, 28, 0); }
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
      let programmaticScrollUntil = 0;
      let scrollProgressTimer = null;
      let pendingPulseHighlightIds = new Set();
      let lastSavedSelection = { signature: null, savedAt: 0 };
      const speedSwipeEdgeWidth = 84;

      const progress = () => {
        const documentHeight = Math.max(document.documentElement.scrollHeight, document.body.scrollHeight);
        const viewportHeight = window.innerHeight || 1;
        const maxScroll = Math.max(1, documentHeight - viewportHeight);
        const chapter = chapterAtScrollPosition();
        const chapterInfo = chapterProgressForScroll(chapter);
        return {
          scrollY: window.scrollY,
          documentHeight,
          viewportHeight,
          totalProgression: Math.max(0, Math.min(1, window.scrollY / maxScroll)),
          spineIndex: chapterInfo.spineIndex,
          href: chapterInfo.href,
          chapterTitle: chapterInfo.chapterTitle,
          chapterProgression: chapterInfo.chapterProgression
        };
      };

      const chapterAtScrollPosition = () => {
        const chapters = Array.from(document.querySelectorAll('.rf-chapter'));
        if (chapters.length === 0) {
          return null;
        }
        const viewportAnchor = window.scrollY + Math.max(1, window.innerHeight || 1) * 0.22;
        let current = chapters[0];
        for (const chapter of chapters) {
          const rect = chapter.getBoundingClientRect();
          const top = window.scrollY + rect.top;
          if (top <= viewportAnchor) {
            current = chapter;
          } else {
            break;
          }
        }
        return current;
      };

      const chapterProgressForScroll = (chapter) => {
        if (!chapter || !chapter.dataset) {
          return { spineIndex: 0, href: '', chapterTitle: null, chapterProgression: 0 };
        }
        const rect = chapter.getBoundingClientRect();
        const top = window.scrollY + rect.top;
        const height = Math.max(1, chapter.scrollHeight || rect.height || 1);
        const viewportAnchor = window.scrollY + Math.max(1, window.innerHeight || 1) * 0.22;
        return {
          spineIndex: Number(chapter.dataset.spineIndex || 0) || 0,
          href: chapter.dataset.href || '',
          chapterTitle: chapter.dataset.title || null,
          chapterProgression: Math.max(0, Math.min(1, (viewportAnchor - top) / height))
        };
      };

      const markProgrammaticScroll = (duration = 700) => {
        programmaticScrollUntil = Date.now() + duration;
      };

      const scheduleProgressPost = (delay = 120) => {
        if (scrollProgressTimer) {
          clearTimeout(scrollProgressTimer);
        }
        scrollProgressTimer = setTimeout(() => {
          scrollProgressTimer = null;
          post('progressChanged', progress());
        }, delay);
      };

      const scrollToY = (target) => {
        const documentHeight = Math.max(document.documentElement.scrollHeight, document.body.scrollHeight);
        const viewportHeight = window.innerHeight || 1;
        const maxScroll = Math.max(0, documentHeight - viewportHeight);
        const boundedTarget = Math.max(0, Math.min(maxScroll, Number(target) || 0));
        const root = document.documentElement;
        const body = document.body;
        const previousRootScrollBehavior = root.style.scrollBehavior;
        const previousBodyScrollBehavior = body.style.scrollBehavior;
        markProgrammaticScroll();
        root.style.scrollBehavior = 'auto';
        body.style.scrollBehavior = 'auto';
        window.scrollTo({ top: boundedTarget, left: 0, behavior: 'instant' });
        root.style.scrollBehavior = previousRootScrollBehavior;
        body.style.scrollBehavior = previousBodyScrollBehavior;
        post('progressChanged', progress());
      };

      const scrollToElement = (element) => {
        const rect = element.getBoundingClientRect();
        scrollToY(window.scrollY + rect.top);
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
        markProgrammaticScroll(120);
        window.scrollBy(0, speed * delta);
        if (time - lastProgressPost > 1000) {
          lastProgressPost = time;
          post('progressChanged', progress());
        }
        const current = progress();
        if (current.totalProgression >= 1) {
          running = false;
          post('progressChanged', current);
          post('scrollStateChanged', { running: false, reason: 'end' });
          return;
        }
        requestAnimationFrame(tick);
      };

      const pauseForManualScroll = () => {
        if (!running) {
          return;
        }
        running = false;
        lastTime = null;
        scheduleProgressPost(140);
        post('scrollStateChanged', { running: false, reason: 'manualScroll' });
      };

      const pauseForSelection = () => {
        if (!running) {
          return;
        }
        running = false;
        lastTime = null;
        scheduleProgressPost(120);
        post('scrollStateChanged', { running: false, reason: 'selection' });
      };

      const isRightEdgeTouch = (touch) => touch.clientX >= Math.max(0, window.innerWidth - speedSwipeEdgeWidth);

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

      const highlightElement = (highlightId) => {
        const id = String(highlightId || '');
        if (!id) {
          return null;
        }
        return Array.from(document.querySelectorAll('.rf-highlight'))
          .find((element) => element.dataset && element.dataset.highlightId === id) || null;
      };

      const removeHighlightElement = (element) => {
        try {
          const parent = element.parentNode;
          if (!parent) {
            element.remove();
            return;
          }
          while (element.firstChild) {
            parent.insertBefore(element.firstChild, element);
          }
          element.remove();
          parent.normalize();
        } catch (_) {
          if (element.remove) {
            element.remove();
          }
        }
      };

      const syncHighlightElements = (highlightIds) => {
        Array.from(document.querySelectorAll('.rf-highlight')).forEach((element) => {
          const id = element.dataset && element.dataset.highlightId;
          if (id && !highlightIds.has(id)) {
            removeHighlightElement(element);
          }
        });
      };

      const wrapRangeInHighlight = (range, highlightId) => {
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

      const markRange = (range, highlightId) => {
        if (highlightElement(highlightId)) {
          return true;
        }
        if (wrapRangeInHighlight(range, highlightId)) {
          return true;
        }
        try {
          const marker = document.createElement('mark');
          marker.className = 'rf-highlight';
          marker.dataset.highlightId = highlightId;
          const contents = range.extractContents();
          marker.appendChild(contents);
          range.insertNode(marker);
          return true;
        } catch (_) {
          return false;
        }
      };

      const markSelection = (range, highlightId) => markRange(range, highlightId);

      const textNodesIn = (root) => {
        const nodes = [];
        const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
        let node = walker.nextNode();
        while (node) {
          if (node.nodeValue && node.nodeValue.trim().length > 0) {
            nodes.push(node);
          }
          node = walker.nextNode();
        }
        return nodes;
      };

      const normalizeQuoteText = (value) => String(value || '').replace(/[\\s\\u00a0]+/g, ' ').trim();

      const normalizedSegments = (nodes) => {
        let normalizedText = '';
        const offsetMap = [];
        const segments = [];
        let rawOffset = 0;

        nodes.forEach((node) => {
          const text = node.nodeValue || '';
          const segment = { node, text, start: rawOffset };
          segments.push(segment);
          for (let index = 0; index < text.length; index += 1) {
            const character = text[index];
            const isWhitespace = /[\\s\\u00a0]/.test(character);
            if (isWhitespace) {
              if (normalizedText.length > 0 && !normalizedText.endsWith(' ')) {
                normalizedText += ' ';
                offsetMap.push(rawOffset + index);
              }
            } else {
              normalizedText += character;
              offsetMap.push(rawOffset + index);
            }
          }
          rawOffset += text.length;
        });

        while (normalizedText.endsWith(' ')) {
          normalizedText = normalizedText.slice(0, -1);
          offsetMap.pop();
        }
        return { normalizedText, offsetMap, segments };
      };

      const locateTextOffset = (segments, offset) => {
        for (const segment of segments) {
          const localOffset = offset - segment.start;
          if (localOffset >= 0 && localOffset <= segment.text.length) {
            return { node: segment.node, offset: localOffset };
          }
        }
        const last = segments[segments.length - 1];
        return last ? { node: last.node, offset: last.text.length } : null;
      };

      const rangeForTextQuote = (chapter, exact, prefix, suffix) => {
        const text = normalizeQuoteText(exact);
        if (!chapter || text.length < 2) {
          return null;
        }
        const nodes = textNodesIn(chapter);
        const { normalizedText, offsetMap, segments } = normalizedSegments(nodes);
        const fullText = normalizedText;
        if (!fullText || segments.length === 0) {
          return null;
        }

        const trimmedPrefix = normalizeQuoteText(prefix);
        const trimmedSuffix = normalizeQuoteText(suffix);
        const hasContext = trimmedPrefix.length > 0 || trimmedSuffix.length > 0;
        let best = null;
        let searchFrom = 0;
        while (searchFrom < fullText.length) {
          const start = fullText.indexOf(text, searchFrom);
          if (start < 0) {
            break;
          }
          const end = start + text.length;
          const before = fullText.slice(Math.max(0, start - Math.max(80, trimmedPrefix.length)), start).trim();
          const after = fullText.slice(end, end + Math.max(80, trimmedSuffix.length)).trim();
          let score = 0;
          if (trimmedPrefix && before.endsWith(trimmedPrefix)) {
            score += 2;
          }
          if (trimmedSuffix && after.startsWith(trimmedSuffix)) {
            score += 2;
          }
          if (!best || score > best.score) {
            best = { start, end, score };
          }
          if (score >= 4) {
            break;
          }
          searchFrom = start + Math.max(1, text.length);
        }

        if (!best || (hasContext && best.score === 0)) {
          return null;
        }
        const rawStart = offsetMap[best.start];
        const rawEnd = (offsetMap[best.end - 1] ?? rawStart) + 1;
        const startPosition = locateTextOffset(segments, rawStart);
        const endPosition = locateTextOffset(segments, rawEnd);
        if (!startPosition || !endPosition) {
          return null;
        }
        const range = document.createRange();
        range.setStart(startPosition.node, startPosition.offset);
        range.setEnd(endPosition.node, endPosition.offset);
        return range;
      };

      const applyHighlight = (highlight) => {
        if (!highlight || !highlight.id || highlightElement(highlight.id)) {
          return false;
        }
        const locator = highlight.locator || {};
        const chapter = chapterForHref(locator.href) || document.querySelector('.rf-chapter');
        const range = rangeForTextQuote(
          chapter,
          highlight.selectedText,
          highlight.contextBefore || (locator.textQuote && locator.textQuote.prefix),
          highlight.contextAfter || (locator.textQuote && locator.textQuote.suffix)
        );
        return range ? markRange(range, highlight.id) : false;
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

      const selectionSignature = (payload) => [
        payload.selectedText,
        payload.contextBefore,
        payload.contextAfter,
        payload.locator.href,
        Math.round((payload.locator.chapterProgression || 0) * 10000)
      ].join('\\u001f');

      const shouldSuppressDuplicateSelection = (payload) => {
        const signature = selectionSignature(payload);
        const now = Date.now();
        if (lastSavedSelection.signature === signature && now - lastSavedSelection.savedAt <= 3000) {
          return true;
        }
        lastSavedSelection.signature = signature;
        lastSavedSelection.savedAt = now;
        return false;
      };

      document.addEventListener('selectionchange', () => {
        const activeSelection = window.getSelection();
        if (activeSelection && !activeSelection.isCollapsed) {
          pauseForSelection();
        }
        clearTimeout(window.__readerFlowSelectionTimer);
        window.__readerFlowSelectionTimer = setTimeout(() => {
          const payload = selectionPayload();
          if (!payload) return;
          if (shouldSuppressDuplicateSelection(payload)) {
            window.getSelection().removeAllRanges();
            return;
          }
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
        touchStart = {
          x: touch.clientX,
          y: touch.clientY,
          speedEdge: isRightEdgeTouch(touch),
          moved: false
        };
      }, { passive: true });

      document.addEventListener('touchmove', (event) => {
        if (!touchStart || event.touches.length !== 1) {
          return;
        }
        const touch = event.touches[0];
        const dx = touch.clientX - touchStart.x;
        const dy = touch.clientY - touchStart.y;
        if (Math.abs(dx) > 8 || Math.abs(dy) > 8) {
          touchStart.moved = true;
        }
        if (touchStart.speedEdge && Math.abs(dy) > 8 && Math.abs(dy) > Math.abs(dx) * 1.2) {
          event.preventDefault();
          return;
        }
        if (running && Math.abs(dy) > 10 && Math.abs(dy) > Math.abs(dx)) {
          pauseForManualScroll();
        }
      }, { passive: false });

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
        const wasSpeedEdge = touchStart.speedEdge;
        const moved = touchStart.moved;
        touchStart = null;

        if (moved) {
          suppressClickUntil = Date.now() + 300;
        }

        if (!wasSpeedEdge) {
          return;
        }

        if (Math.abs(dy) < 52 || Math.abs(dy) < Math.abs(dx) * 1.5) {
          return;
        }

        event.preventDefault();
        suppressClickUntil = Date.now() + 450;
        post('speedAdjustment', { delta: dy < 0 ? 5 : -5 });
      }, { passive: false });

      window.addEventListener('wheel', () => {
        pauseForManualScroll();
      }, { passive: true });

      window.addEventListener('scroll', () => {
        if (running && Date.now() > programmaticScrollUntil) {
          pauseForManualScroll();
        }
        if (!running) {
          scheduleProgressPost(120);
        }
      }, { passive: true });

      const chapterForHref = (value) => {
        const href = String(value || '').split('#')[0];
        if (!href) {
          return null;
        }
        const chapters = Array.from(document.querySelectorAll('.rf-chapter'));
        return chapters.find((chapter) => chapter.dataset.normalizedHref === href || chapter.dataset.href === href) || null;
      };

      const scrollToChapterProgress = (chapter, value) => {
        const chapterProgress = Math.max(0, Math.min(1, Number(value) || 0));
        const chapterRect = chapter.getBoundingClientRect();
        const chapterTop = window.scrollY + chapterRect.top;
        const chapterHeight = Math.max(1, chapter.scrollHeight || chapterRect.height || 1);
        const viewportAnchorOffset = Math.max(1, window.innerHeight || 1) * 0.22;
        scrollToY(chapterTop + chapterHeight * chapterProgress - viewportAnchorOffset);
      };

      const finiteNumber = (value) => value !== null && value !== undefined && Number.isFinite(Number(value));

      window.ReaderFlow = {
        setSpeed(value) {
          speed = Number(value) || 25;
        },
        scrollToProgress(value) {
          const target = Math.max(0, Math.min(1, Number(value) || 0));
          const documentHeight = Math.max(document.documentElement.scrollHeight, document.body.scrollHeight);
          const viewportHeight = window.innerHeight || 1;
          const maxScroll = Math.max(0, documentHeight - viewportHeight);
          scrollToY(maxScroll * target);
        },
        scrollToHref(value) {
          const target = chapterForHref(value);
          if (!target) {
            return;
          }
          scrollToElement(target);
        },
        scrollToLocator(href, chapterProgression, fallbackProgress, scrollY, storedDocumentHeight) {
          const currentDocumentHeight = Math.max(document.documentElement.scrollHeight, document.body.scrollHeight);
          if (finiteNumber(scrollY) && finiteNumber(storedDocumentHeight)) {
            const heightDelta = Math.abs(currentDocumentHeight - Number(storedDocumentHeight));
            if (heightDelta / Math.max(1, Number(storedDocumentHeight)) <= 0.1) {
              scrollToY(scrollY);
              return;
            }
          }
          const target = chapterForHref(href);
          if (target && finiteNumber(chapterProgression)) {
            scrollToChapterProgress(target, chapterProgression);
            return;
          }
          if (target) {
            scrollToElement(target);
            return;
          }
          if (finiteNumber(fallbackProgress)) {
            this.scrollToProgress(fallbackProgress);
          }
        },
        applyHighlights(highlights) {
          if (!Array.isArray(highlights)) {
            return;
          }
          const highlightIds = new Set(highlights.map((highlight) => String(highlight && highlight.id || '')).filter(Boolean));
          syncHighlightElements(highlightIds);
          highlights.forEach(applyHighlight);
          Array.from(pendingPulseHighlightIds).forEach((highlightId) => {
            if (this.pulseHighlight(highlightId)) {
              pendingPulseHighlightIds.delete(highlightId);
            }
          });
        },
        pulseHighlight(highlightId) {
          const element = highlightElement(highlightId);
          if (!element) {
            const id = String(highlightId || '');
            if (id) {
              pendingPulseHighlightIds.add(id);
            }
            return false;
          }
          const rect = element.getBoundingClientRect();
          const target = window.scrollY + rect.top - Math.max(1, window.innerHeight || 1) * 0.42;
          scrollToY(target);
          element.classList.remove('rf-highlight-pulse');
          void element.offsetWidth;
          element.classList.add('rf-highlight-pulse');
          setTimeout(() => {
            element.classList.remove('rf-highlight-pulse');
          }, 1300);
          return true;
        },
        start() {
          if (!running) {
            running = true;
            requestAnimationFrame(tick);
            post('scrollStateChanged', { running: true });
          }
        },
        pause() {
          if (!running) {
            return;
          }
          running = false;
          post('progressChanged', progress());
          post('scrollStateChanged', { running: false });
        }
      };

      post('readerReady', progress());
    })();
    """
}
