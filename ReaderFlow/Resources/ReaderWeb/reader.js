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
