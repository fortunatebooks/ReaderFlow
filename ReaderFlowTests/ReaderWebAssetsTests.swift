import Foundation
import JavaScriptCore
@testable import ReaderFlow
import Testing

struct ReaderWebAssetsTests {
    @Test func readerScriptIncludesManualScrollPauseBehavior() {
        let javascript = ReaderWebAssets.javascript

        #expect(javascript.contains("pauseForManualScroll"))
        #expect(javascript.contains("reason: 'manualScroll'"))
        #expect(javascript.contains("speedSwipeEdgeWidth"))
        #expect(javascript.contains("isRightEdgeTouch"))
        #expect(javascript.contains("reason: 'end'"))
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

    @Test func manualScrollWhileRunningPausesAndDebouncesProgress() throws {
        let harness = try ReaderScriptHarness()

        try harness.evaluate("messages = []; now = 1000; window.ReaderFlow.start(); window.scrollY = 220; dispatchWindow('scroll', {});")

        #expect(try harness.int(manualPauseCountExpression) == 1)
        #expect(try harness.int("messages.filter(function(message) { return message.type === 'progressChanged'; }).length") == 0)

        try harness.evaluate("flushTimers();")

        #expect(try harness.int("messages.filter(function(message) { return message.type === 'progressChanged' && message.payload.scrollY === 220; }).length") == 1)
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
    var now = 0;
    var timerId = 0;
    var timers = {};
    Date.now = function() { return now; };
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
    var chapters = [
      {
        dataset: { spineIndex: '0', href: 'Text/chapter1.xhtml', normalizedHref: 'OPS/Text/chapter1.xhtml', title: 'Chapter 1' },
        scrollHeight: 1000,
        getBoundingClientRect: function() { return { top: 0 - window.scrollY, height: 1000 }; },
        closest: function(selector) { return selector === '.rf-chapter' ? this : null; }
      },
      {
        dataset: { spineIndex: '1', href: 'Text/chapter2.xhtml', normalizedHref: 'OPS/Text/chapter2.xhtml', title: 'Chapter 2' },
        scrollHeight: 1000,
        getBoundingClientRect: function() { return { top: 1000 - window.scrollY, height: 1000 }; },
        closest: function(selector) { return selector === '.rf-chapter' ? this : null; }
      }
    ];
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
        return {
          isCollapsed: true,
          rangeCount: 0,
          getRangeAt: function() { return null; },
          removeAllRanges: function() {}
        };
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
        return selector === '.rf-chapter' ? chapters : [];
      },
      querySelector: function(selector) {
        return selector === '.rf-chapter' ? chapters[0] : null;
      },
      createElement: function() { return {}; },
      createRange: function() {
        return {
          selectNodeContents: function() {},
          setEnd: function() {},
          setStart: function() {},
          toString: function() { return ''; }
        };
      }
    };
    var Node = { TEXT_NODE: 3 };
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
