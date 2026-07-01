import Foundation
import JavaScriptCore
@testable import ReaderFlow
import Testing

struct ReaderWebAssetsTests {
    @Test func readerScriptIncludesManualScrollPauseBehavior() {
        let javascript = ReaderWebAssets.javascript

        #expect(javascript.contains("pauseForManualScroll"))
        #expect(javascript.contains("reason: 'manualScroll'"))
        #expect(javascript.contains("reason: 'selection'"))
        #expect(javascript.contains("speedSwipeEdgeWidth"))
        #expect(javascript.contains("isRightEdgeTouch"))
        #expect(javascript.contains("reason: 'end'"))
        #expect(javascript.contains("applyHighlights"))
        #expect(javascript.contains("pulseHighlight"))
        #expect(javascript.contains("shouldSuppressDuplicateSelection"))
    }

    @Test func readerScriptMarksRestoreAndNavigationScrollsAsProgrammatic() {
        let javascript = normalizedScript

        #expect(javascript.contains("const markProgrammaticScroll = (duration = 700) =>"))
        #expect(javascript.contains("root.style.scrollBehavior = 'auto';"))
        #expect(javascript.contains("body.style.scrollBehavior = 'auto';"))
        #expect(javascript.contains("window.scrollTo({ top: boundedTarget, left: 0, behavior: 'instant' });"))
        #expect(!javascript.contains("scrollIntoView"))
    }

    @Test func readerScriptSuppressesMovedEdgeGesturesBeforeSpeedThresholdCheck() {
        let javascript = normalizedScript

        #expect(javascript.contains("touchStart.speedEdge && Math.abs(dy) > 8"))
        #expect(javascript.contains("if (moved) { suppressClickUntil = Date.now() + 300; } if (!wasSpeedEdge)"))
        #expect(javascript.contains("if (Math.abs(dy) < 52 || Math.abs(dy) < Math.abs(dx) * 1.5)"))
    }

    @Test func readerScriptDebouncesProgressAfterManualScrollSettles() {
        let javascript = normalizedScript

        #expect(javascript.contains("const scheduleProgressPost = (delay = 120) =>"))
        #expect(javascript.contains("scheduleProgressPost(140); post('scrollStateChanged', { running: false, reason: 'manualScroll' });"))
        #expect(javascript.contains("if (!running) { scheduleProgressPost(120); }"))
    }

    @Test func rightEdgeSpeedSwipeDoesNotPauseBeforeSpeedThreshold() throws {
        let harness = try ReaderScriptHarness()

        try harness.evaluate("messages = []; window.ReaderFlow.start();")
        try harness.evaluate(
            """
            listeners.document.touchstart({ touches: [{ clientX: 390, clientY: 100 }] });
            var edgePrevented = false;
            listeners.document.touchmove({
              touches: [{ clientX: 390, clientY: 112 }],
              preventDefault: function() { edgePrevented = true; }
            });
            """
        )

        #expect(try harness.bool("edgePrevented"))
        #expect(try harness.int(manualPauseCountExpression) == 0)
    }

    @Test func programmaticScrollWhileRunningDoesNotPause() throws {
        let harness = try ReaderScriptHarness()

        try harness.evaluate("messages = []; now = 0; window.ReaderFlow.start(); window.ReaderFlow.scrollToProgress(0.5);")

        #expect(try harness.int(manualPauseCountExpression) == 0)
        #expect(try harness.int("window.scrollY") == 750)
        #expect(try harness.string("document.documentElement.style.scrollBehavior") == "")
        #expect(try harness.string("document.body.style.scrollBehavior") == "")
    }

    @Test func progressMessagesIncludeCurrentChapterLocatorFields() throws {
        let harness = try ReaderScriptHarness()

        try harness.evaluate("messages = []; window.ReaderFlow.scrollToProgress(0.4);")

        #expect(try harness.int("messages.filter(function(message) { return message.type === 'progressChanged' && message.payload.href === 'Text/chapter1.xhtml'; }).length") == 1)
        #expect(try harness.int("messages.filter(function(message) { return message.type === 'progressChanged' && message.payload.spineIndex === 0; }).length") == 1)
        #expect(try harness.string("messages[messages.length - 1].payload.chapterTitle") == "Chapter 1")
        #expect(try abs(harness.double("messages[messages.length - 1].payload.chapterProgression") - 0.71) < 0.0001)
    }

    @Test func scrollToLocatorPrefersExactScrollWhenDocumentHeightMatches() throws {
        let harness = try ReaderScriptHarness()

        try harness.evaluate("window.ReaderFlow.scrollToLocator('Text/chapter2.xhtml', 0.5, 0.1, 700, 2000);")

        #expect(try harness.int("window.scrollY") == 700)
    }

    @Test func scrollToLocatorFallsBackToChapterWhenDocumentHeightChanged() throws {
        let harness = try ReaderScriptHarness()

        try harness.evaluate("window.ReaderFlow.scrollToLocator('Text/chapter2.xhtml', 0.5, 0.1, 700, 1000);")

        #expect(try harness.int("window.scrollY") == 1390)
    }

    @Test func applyHighlightsMarksSavedExcerptByTextAndContext() throws {
        let harness = try ReaderScriptHarness()

        try harness.evaluate(
            """
            window.ReaderFlow.applyHighlights([{
              id: 'highlight-1',
              selectedText: 'saved passage',
              contextBefore: 'Intro',
              contextAfter: 'outro',
              locator: { href: 'Text/chapter1.xhtml' }
            }]);
            """
        )

        #expect(try harness.int("highlightElements.length") == 1)
        #expect(try harness.string("highlightElements[0].dataset.highlightId") == "highlight-1")
    }

    @Test func applyHighlightsMatchesCollapsedWhitespace() throws {
        let harness = try ReaderScriptHarness()

        try harness.evaluate(
            """
            window.ReaderFlow.applyHighlights([{
              id: 'highlight-1',
              selectedText: 'saved passage',
              contextBefore: 'Intro',
              contextAfter: 'outro',
              locator: { href: 'Text/chapter1.xhtml' }
            }]);
            """
        )

        #expect(try harness.int("highlightElements.length") == 1)
        #expect(try harness.string("highlightElements[0].text").contains("saved"))
    }

    @Test func applyHighlightsDoesNotMarkAmbiguousTextWithoutMatchingContext() throws {
        let harness = try ReaderScriptHarness()

        try harness.evaluate(
            """
            window.ReaderFlow.applyHighlights([{
              id: 'highlight-1',
              selectedText: 'saved passage',
              contextBefore: 'Missing prefix',
              contextAfter: 'Missing suffix',
              locator: { href: 'Text/chapter1.xhtml' }
            }]);
            """
        )

        #expect(try harness.int("highlightElements.length") == 0)
    }

    @Test func applyHighlightsSkipsAlreadyMarkedExcerpt() throws {
        let harness = try ReaderScriptHarness()

        try harness.evaluate(
            """
            const savedHighlight = {
              id: 'highlight-1',
              selectedText: 'saved passage',
              contextBefore: 'Intro',
              contextAfter: 'outro',
              locator: { href: 'Text/chapter1.xhtml' }
            };
            window.ReaderFlow.applyHighlights([savedHighlight]);
            window.ReaderFlow.applyHighlights([savedHighlight]);
            """
        )

        #expect(try harness.int("highlightElements.length") == 1)
    }

    @Test func applyHighlightsRemovesDeletedExcerptMarks() throws {
        let harness = try ReaderScriptHarness()

        try harness.evaluate(
            """
            window.ReaderFlow.applyHighlights([
              {
                id: 'highlight-1',
                selectedText: 'saved passage',
                contextBefore: 'Intro',
                contextAfter: 'outro',
                locator: { href: 'Text/chapter1.xhtml' }
              },
              {
                id: 'highlight-2',
                selectedText: 'Second chapter',
                contextBefore: '',
                contextAfter: 'text',
                locator: { href: 'Text/chapter2.xhtml' }
              }
            ]);
            window.ReaderFlow.applyHighlights([{
              id: 'highlight-2',
              selectedText: 'Second chapter',
              contextBefore: '',
              contextAfter: 'text',
              locator: { href: 'Text/chapter2.xhtml' }
            }]);
            """
        )

        #expect(try harness.int("highlightElements.length") == 1)
        #expect(try harness.string("highlightElements[0].dataset.highlightId") == "highlight-2")
    }

    @Test func pulseHighlightScrollsAndAddsPulseClass() throws {
        let harness = try ReaderScriptHarness()

        try harness.evaluate(
            """
            window.ReaderFlow.applyHighlights([{
              id: 'highlight-1',
              selectedText: 'saved passage',
              contextBefore: 'Intro',
              contextAfter: 'outro',
              locator: { href: 'Text/chapter1.xhtml' }
            }]);
            var didPulse = window.ReaderFlow.pulseHighlight('highlight-1');
            """
        )

        #expect(try harness.bool("didPulse"))
        #expect(try harness.int("window.scrollY") == 90)
        #expect(try harness.bool("highlightElements[0].classList.contains('rf-highlight-pulse')"))
        #expect(try harness.int(manualPauseCountExpression) == 0)
    }

    @Test func pendingPulseRetriesAfterHighlightIsApplied() throws {
        let harness = try ReaderScriptHarness()

        try harness.evaluate(
            """
            var firstPulse = window.ReaderFlow.pulseHighlight('highlight-1');
            window.ReaderFlow.applyHighlights([{
              id: 'highlight-1',
              selectedText: 'saved passage',
              contextBefore: 'Intro',
              contextAfter: 'outro',
              locator: { href: 'Text/chapter1.xhtml' }
            }]);
            """
        )

        #expect(try !harness.bool("firstPulse"))
        #expect(try harness.bool("highlightElements[0].classList.contains('rf-highlight-pulse')"))
    }

    @Test func manualScrollWhileRunningPausesAndDebouncesProgress() throws {
        let harness = try ReaderScriptHarness()

        try harness.evaluate("messages = []; now = 1000; window.ReaderFlow.start(); window.scrollY = 220; dispatchWindow('scroll', {});")

        #expect(try harness.int(manualPauseCountExpression) == 1)
        #expect(try harness.int("messages.filter(function(message) { return message.type === 'progressChanged'; }).length") == 0)

        try harness.evaluate("flushTimers();")

        #expect(try harness.int("messages.filter(function(message) { return message.type === 'progressChanged' && message.payload.scrollY === 220; }).length") == 1)
    }

    @Test func selectionWhileRunningPausesAndSavesExcerpt() throws {
        let harness = try ReaderScriptHarness()

        try harness.evaluate(
            """
            messages = [];
            now = 1000;
            window.ReaderFlow.start();
            activeSelection = makeSelection(1, 0, 14);
            listeners.document.selectionchange({});
            flushTimers();
            """
        )

        #expect(try harness.int("messages.filter(function(message) { return message.type === 'scrollStateChanged' && message.payload.reason === 'selection'; }).length") == 1)
        #expect(try harness.int("messages.filter(function(message) { return message.type === 'selectionSaved'; }).length") == 1)
        #expect(try harness.string("messages.filter(function(message) { return message.type === 'selectionSaved'; })[0].payload.selectedText") == "Second chapter")
    }

    @Test func duplicateSelectionWithinThreeSecondsIsSuppressed() throws {
        let harness = try ReaderScriptHarness()

        try harness.evaluate(
            """
            messages = [];
            now = 1000;
            activeSelection = makeSelection(1, 0, 14);
            listeners.document.selectionchange({});
            flushTimers();
            activeSelection = makeSelection(1, 0, 14);
            listeners.document.selectionchange({});
            flushTimers();
            now = 4501;
            activeSelection = makeSelection(1, 0, 14);
            listeners.document.selectionchange({});
            flushTimers();
            """
        )

        #expect(try harness.int("messages.filter(function(message) { return message.type === 'selectionSaved'; }).length") == 2)
        #expect(try harness.int("highlightElements.length") == 2)
    }

    @Test func pauseCommandIsIdempotentToAvoidBridgeEcho() throws {
        let harness = try ReaderScriptHarness()

        try harness.evaluate("messages = []; window.ReaderFlow.pause();")
        #expect(try harness.int("messages.length") == 0)

        try harness.evaluate("window.ReaderFlow.start(); messages = []; window.ReaderFlow.pause();")
        #expect(try harness.int("messages.filter(function(message) { return message.type === 'scrollStateChanged' && message.payload.running === false; }).length") == 1)
    }

    @Test func decodesReaderScrollStateMessage() throws {
        let json = #"{"running":false,"reason":"manualScroll"}"#
        let message = try JSONDecoder().decode(ReaderScrollStateMessage.self, from: Data(json.utf8))

        #expect(!message.running)
        #expect(message.reason == "manualScroll")
    }

    @Test func decodesReaderProgressChapterLocatorFields() throws {
        let json = #"{"scrollY":600,"documentHeight":2000,"viewportHeight":500,"totalProgression":0.4,"spineIndex":0,"href":"Text/chapter1.xhtml","chapterTitle":"Chapter 1","chapterProgression":0.71}"#
        let message = try JSONDecoder().decode(ReaderProgressMessage.self, from: Data(json.utf8))

        #expect(message.spineIndex == 0)
        #expect(message.href == "Text/chapter1.xhtml")
        #expect(message.chapterTitle == "Chapter 1")
        #expect(abs((message.chapterProgression ?? 0) - 0.71) < 0.0001)
    }

    private var normalizedScript: String {
        ReaderWebAssets.javascript.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )
    }

    private var manualPauseCountExpression: String {
        "messages.filter(function(message) { return message.type === 'scrollStateChanged' && message.payload.reason === 'manualScroll'; }).length"
    }
}

private final class ReaderScriptHarness {
    private let context: JSContext
    private var exception: String?

    init() throws {
        guard let context = JSContext() else {
            throw ReaderScriptHarnessError.noContext
        }
        self.context = context
        context.exceptionHandler = { [weak self] _, exception in
            self?.exception = exception?.toString()
        }
        try evaluate(Self.stubScript)
        try evaluate(ReaderWebAssets.javascript)
    }

    @discardableResult
    func evaluate(_ script: String) throws -> JSValue {
        exception = nil
        guard let value = context.evaluateScript(script) else {
            if let exception {
                throw ReaderScriptHarnessError.exception(exception)
            }
            throw ReaderScriptHarnessError.noValue
        }
        if let exception {
            throw ReaderScriptHarnessError.exception(exception)
        }
        return value
    }

    func int(_ script: String) throws -> Int {
        try Int(evaluate(script).toInt32())
    }

    func bool(_ script: String) throws -> Bool {
        try evaluate(script).toBool()
    }

    func string(_ script: String) throws -> String {
        try evaluate(script).toString()
    }

    func double(_ script: String) throws -> Double {
        try evaluate(script).toDouble()
    }

    private static let stubScript = """
    var messages = [];
    var listeners = { document: {}, window: {} };
    var highlightElements = [];
    var activeSelection = null;
    var now = 0;
    var timerId = 0;
    var uuidCounter = 0;
    var timers = {};
    Date.now = function() { return now; };
    var crypto = {
      randomUUID: function() {
        uuidCounter += 1;
        return '00000000-0000-4000-8000-' + ('000000000000' + uuidCounter).slice(-12);
      }
    };
    function setTimeout(callback, delay) {
      timerId += 1;
      timers[timerId] = callback;
      return timerId;
    }
    function clearTimeout(id) {
      delete timers[id];
    }
    function flushTimers() {
      var ids = Object.keys(timers);
      for (var index = 0; index < ids.length; index += 1) {
        var callback = timers[ids[index]];
        delete timers[ids[index]];
        if (callback) {
          callback();
        }
      }
    }
    function requestAnimationFrame(callback) {}
    function dispatchWindow(type, event) {
      if (listeners.window[type]) {
        listeners.window[type](event || {});
      }
    }
    function makeClassList(element) {
      return {
        values: {},
        add: function(value) { this.values[value] = true; },
        remove: function(value) { delete this.values[value]; },
        contains: function(value) { return this.values[value] === true; }
      };
    }
    function collapsedSelection() {
      return {
        isCollapsed: true,
        rangeCount: 0,
        getRangeAt: function() { return null; },
        removeAllRanges: function() { activeSelection = collapsedSelection(); },
        toString: function() { return ''; }
      };
    }
    function rangeTextBetween(range) {
      if (!range.startContainer || !range.endContainer) {
        return '';
      }
      if (range.startContainer === range.endContainer) {
        return range.startContainer.nodeValue.slice(range.startOffset, range.endOffset);
      }
      const root = range.selectedRoot || range.startContainer.parentElement;
      const nodes = root && root.textNodes ? root.textNodes : [range.startContainer, range.endContainer];
      let text = '';
      let isCollecting = false;
      for (var index = 0; index < nodes.length; index += 1) {
        const node = nodes[index];
        if (node === range.startContainer) {
          isCollecting = true;
          if (node === range.endContainer) {
            return text + node.nodeValue.slice(range.startOffset, range.endOffset);
          }
          text += node.nodeValue.slice(range.startOffset);
        } else if (node === range.endContainer) {
          text += node.nodeValue.slice(0, range.endOffset);
          break;
        } else if (isCollecting) {
          text += node.nodeValue;
        }
      }
      return text;
    }
    function makeSelection(chapterIndex, startOffset, endOffset) {
      const node = chapters[chapterIndex].textNodes[0];
      const range = document.createRange();
      range.setStart(node, startOffset);
      range.setEnd(node, endOffset);
      return {
        isCollapsed: false,
        rangeCount: 1,
        getRangeAt: function() { return range; },
        removeAllRanges: function() { activeSelection = collapsedSelection(); },
        toString: function() { return range.toString(); }
      };
    }
    var chapters = [
      {
        dataset: { spineIndex: '0', href: 'Text/chapter1.xhtml', normalizedHref: 'OPS/Text/chapter1.xhtml', title: 'Chapter 1' },
        scrollHeight: 1000,
        textNodes: [{ nodeValue: 'Intro saved\\u00a0   passage outro. Another saved passage elsewhere.' }],
        getBoundingClientRect: function() { return { top: 0 - window.scrollY, height: 1000 }; },
        closest: function(selector) { return selector === '.rf-chapter' ? this : null; }
      },
      {
        dataset: { spineIndex: '1', href: 'Text/chapter2.xhtml', normalizedHref: 'OPS/Text/chapter2.xhtml', title: 'Chapter 2' },
        scrollHeight: 1000,
        textNodes: [{ nodeValue: 'Second chapter text.' }],
        getBoundingClientRect: function() { return { top: 1000 - window.scrollY, height: 1000 }; },
        closest: function(selector) { return selector === '.rf-chapter' ? this : null; }
      }
    ];
    chapters[0].textNodes[0].parentElement = chapters[0];
    chapters[1].textNodes[0].parentElement = chapters[1];
    var window = {
      __readerFlowBridgeToken: 'test-token',
      __readerFlowBookId: '00000000-0000-0000-0000-000000000000',
      __readerFlowBookFingerprint: 'fingerprint',
      __readerFlowSelectionTimer: null,
      innerHeight: 500,
      innerWidth: 400,
      scrollY: 0,
      webkit: {
        messageHandlers: {
          readerFlow: {
            postMessage: function(message) {
              messages.push(message);
            }
          }
        }
      },
      addEventListener: function(type, handler) {
        listeners.window[type] = handler;
      },
      scrollBy: function(x, y) {
        window.scrollY += y;
        dispatchWindow('scroll', {});
      },
      scrollTo: function(x, y) {
        if (typeof x === 'object') {
          window.scrollY = Number(x.top) || 0;
        } else {
          window.scrollY = Number(y) || 0;
        }
        dispatchWindow('scroll', {});
      },
      getSelection: function() {
        return activeSelection || collapsedSelection();
      }
    };
    var document = {
      documentElement: {
        scrollHeight: 2000,
        style: { scrollBehavior: '' }
      },
      body: {
        scrollHeight: 2000,
        style: { scrollBehavior: '' }
      },
      addEventListener: function(type, handler) {
        listeners.document[type] = handler;
      },
      querySelectorAll: function(selector) {
        if (selector === '.rf-chapter') {
          return chapters;
        }
        if (selector === '.rf-highlight') {
          return highlightElements;
        }
        return [];
      },
      querySelector: function(selector) {
        return selector === '.rf-chapter' ? chapters[0] : null;
      },
      createElement: function() {
        const element = {
          className: '',
          dataset: {},
          classList: null,
          appendChild: function() {},
          parentNode: null,
          firstChild: null,
          getBoundingClientRect: function() { return { top: 300 - window.scrollY, height: 20 }; },
          remove: function() {
            const index = highlightElements.indexOf(this);
            if (index >= 0) {
              highlightElements.splice(index, 1);
            }
          },
          offsetWidth: 1
        };
        element.classList = makeClassList(element);
        return element;
      },
      createTreeWalker: function(root) {
        const nodes = root && root.textNodes ? root.textNodes : [];
        var index = 0;
        return {
          nextNode: function() {
            if (index >= nodes.length) {
              return null;
            }
            const node = nodes[index];
            index += 1;
            return node;
          }
        };
      },
      createRange: function() {
        return {
          selectedRoot: null,
          startContainer: null,
          startNode: null,
          startOffset: 0,
          endContainer: null,
          endNode: null,
          endOffset: 0,
          selectNodeContents: function(root) {
            this.selectedRoot = root;
            const nodes = root && root.textNodes ? root.textNodes : [];
            if (nodes.length > 0) {
              this.setStart(nodes[0], 0);
              this.setEnd(nodes[nodes.length - 1], nodes[nodes.length - 1].nodeValue.length);
            }
          },
          setEnd: function(node, offset) {
            this.endContainer = node;
            this.endNode = node;
            this.endOffset = offset;
          },
          setStart: function(node, offset) {
            this.startContainer = node;
            this.startNode = node;
            this.startOffset = offset;
          },
          getBoundingClientRect: function() {
            const chapter = this.startContainer && this.startContainer.parentElement;
            const baseTop = chapter === chapters[1] ? 1000 : 0;
            return { top: baseTop + 210 - window.scrollY, height: 20 };
          },
          cloneRange: function() {
            const range = document.createRange();
            range.selectedRoot = this.selectedRoot;
            range.setStart(this.startContainer, this.startOffset);
            range.setEnd(this.endContainer, this.endOffset);
            return range;
          },
          surroundContents: function(marker) {
            marker.text = this.toString();
            marker.parentNode = {
              insertBefore: function() {},
              normalize: function() {}
            };
            highlightElements.push(marker);
          },
          extractContents: function() { return {}; },
          insertNode: function(marker) { highlightElements.push(marker); },
          toString: function() { return rangeTextBetween(this); }
        };
      }
    };
    var Node = { TEXT_NODE: 3 };
    var NodeFilter = { SHOW_TEXT: 4 };
    """
}

private enum ReaderScriptHarnessError: Error, CustomStringConvertible {
    case exception(String)
    case noContext
    case noValue

    var description: String {
        switch self {
        case let .exception(message):
            "JavaScript exception: \\(message)"
        case .noContext:
            "Could not create JavaScript context."
        case .noValue:
            "JavaScript evaluation returned no value."
        }
    }
}
