/* Photo Frame plugin playground. Plain classic script, no build step. */
(function () {
  'use strict';

  var EXAMPLES = ['playback', 'clock', 'weather', 'metadata', 'calendar', 'image-info'];
  var EXAMPLE_FILES = ['plugin.json', 'index.html', 'styles.css', 'common.js', 'script.js'];
  var TEXT_EXTENSIONS = /\.(html?|css|m?js|json|svg|md|txt)$/i;
  var DEFAULT_PLACEMENT = { width: 320, height: 160 };
  var MAX_LOGS = 400;

  var els = {};
  var files = new Map();
  var currentEntry = 'index.html';
  var currentFile = 'index.html';
  var manifest = null;
  var manifestId = null;
  var mockState = {};
  var mockConfig = {};
  var mockPlacement = Object.assign({}, DEFAULT_PLACEMENT);
  var storage = new Map();
  var iframe = null;
  var sdkSource = '';
  var autoRun = true;
  var runTimer = null;
  var logs = [];
  var lastValidStateText = '';
  var lastValidConfigText = '';

  function $(id) { return document.getElementById(id); }

  function init() {
    els = {
      exampleSelect: $('example-select'),
      loadExample: $('load-example'),
      folderInput: $('folder-input'),
      run: $('run'),
      autoRun: $('auto-run'),
      status: $('status'),
      fileTabs: $('file-tabs'),
      sourceEditor: $('source-editor'),
      stateEditor: $('state-editor'),
      configEditor: $('config-editor'),
      applyInputs: $('apply-inputs'),
      resetInputs: $('reset-inputs'),
      inputStatus: $('input-status'),
      hintInputs: $('hint-inputs'),
      hintActions: $('hint-actions'),
      logList: $('log-list'),
      logCount: $('log-count'),
      clearLogs: $('clear-logs'),
      previewDims: $('preview-dims'),
      previewSurface: $('preview-surface'),
      previewEmpty: $('preview-empty'),
      previewShell: $('preview-shell'),
      outline: $('outline'),
      toast: $('toast')
    };

    sdkSource = window.__PHOTOFRAME_HOST_SDK_SOURCE || '';
    bindEvents();
    fitPreview();

    if (!sdkSource) {
      setStatus('host-sdk.js did not load.', 'error');
      addLog('error', 'Missing SDK source. Check host-sdk.js.');
      return;
    }

    addLog('info', 'Playground ready. Loading playback example…');
    loadExample('playback');
  }

  function bindEvents() {
    els.loadExample.addEventListener('click', function () {
      loadExample(els.exampleSelect.value);
    });
    els.exampleSelect.addEventListener('change', function () {
      loadExample(els.exampleSelect.value);
    });
    els.folderInput.addEventListener('change', function (event) {
      loadFolder(event.target.files);
    });
    els.run.addEventListener('click', function () { runPreview(); });
    els.autoRun.addEventListener('change', function () {
      autoRun = els.autoRun.checked;
      addLog('debug', 'Auto-run ' + (autoRun ? 'enabled' : 'disabled'));
    });
    els.sourceEditor.addEventListener('input', function () {
      if (!currentFile) { return; }
      files.set(currentFile, els.sourceEditor.value);
      if (autoRun) { scheduleRun(); }
    });
    els.applyInputs.addEventListener('click', applyInputs);
    els.resetInputs.addEventListener('click', function () {
      resetMockInputs(false);
    });
    els.clearLogs.addEventListener('click', clearLogs);
    els.outline.addEventListener('change', function () {
      els.previewShell.classList.toggle('outline', els.outline.checked);
    });
    document.addEventListener('keydown', function (event) {
      if ((event.ctrlKey || event.metaKey) && event.key === 'Enter') {
        event.preventDefault();
        runPreview();
      }
    });
    window.addEventListener('resize', fitPreview);
    window.addEventListener('message', onWindowMessage);

    document.querySelectorAll('.tab').forEach(function (tab) {
      tab.addEventListener('click', function () {
        switchTab(tab.dataset.tab);
      });
    });
  }

  function switchTab(name) {
    document.querySelectorAll('.tab').forEach(function (tab) {
      tab.classList.toggle('active', tab.dataset.tab === name);
    });
    document.querySelectorAll('.tab-panel').forEach(function (panel) {
      panel.classList.toggle('active', panel.id === 'tab-' + name);
    });
    if (name === 'logs') { scrollLogs(); }
  }

  function setStatus(text, kind) {
    els.status.textContent = text;
    els.status.className = 'status' + (kind ? ' ' + kind : '');
  }

  function toast(message, kind) {
    els.toast.textContent = message;
    els.toast.className = 'toast' + (kind ? ' ' + kind : '');
    els.toast.hidden = false;
    window.clearTimeout(toast._timer);
    toast._timer = window.setTimeout(function () { els.toast.hidden = true; }, 3800);
  }

  function addLog(level, message, detail) {
    var text = String(message == null ? '' : message);
    if (detail !== undefined) {
      try { text += '\n' + JSON.stringify(detail, null, 2); }
      catch (error) { text += '\n' + String(detail); }
    }
    var entry = { time: new Date(), level: level || 'info', message: text };
    logs.push(entry);
    if (logs.length > MAX_LOGS) { logs.shift(); }
    var item = document.createElement('li');
    item.className = 'log-item';
    var time = document.createElement('span');
    time.className = 'log-time';
    time.textContent = formatTime(entry.time);
    var lvl = document.createElement('span');
    lvl.className = 'log-level ' + entry.level;
    lvl.textContent = entry.level;
    var msg = document.createElement('span');
    msg.className = 'log-message';
    msg.textContent = entry.message;
    item.appendChild(time);
    item.appendChild(lvl);
    item.appendChild(msg);
    els.logList.appendChild(item);
    els.logCount.textContent = String(logs.length);
    scrollLogs();
  }

  function formatTime(date) {
    return date.toLocaleTimeString([], { hour12: false }) + '.' +
      String(date.getMilliseconds()).padStart(3, '0');
  }

  function scrollLogs() {
    if (els.logList) { els.logList.scrollTop = els.logList.scrollHeight; }
  }

  function clearLogs() {
    logs = [];
    els.logList.innerHTML = '';
    els.logCount.textContent = '0';
    addLog('debug', 'Logs cleared');
  }

  function scheduleRun() {
    window.clearTimeout(runTimer);
    runTimer = window.setTimeout(runPreview, 500);
  }

  function parseJson(text, label) {
    try {
      return JSON.parse(text);
    } catch (error) {
      throw new Error(label + ' is not valid JSON: ' + error.message);
    }
  }

  function parseManifest(map) {
    if (!map.has('plugin.json')) {
      throw new Error('Missing plugin.json at the bundle root.');
    }
    var raw = map.get('plugin.json');
    var parsed = parseJson(raw, 'plugin.json');
    if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
      throw new Error('plugin.json must be a JSON object.');
    }
    if (!parsed.entry || typeof parsed.entry !== 'string') {
      throw new Error('plugin.json is missing a string "entry".');
    }
    if (!map.has(parsed.entry)) {
      throw new Error('Entry file "' + parsed.entry + '" was not loaded.');
    }
    return parsed;
  }

  async function fetchText(url) {
    var response = await fetch(url, { cache: 'no-store' });
    if (!response.ok) {
      throw new Error('HTTP ' + response.status + ' for ' + url);
    }
    return response.text();
  }

  async function loadExample(name) {
    setStatus('Loading ' + name + '…');
    els.exampleSelect.value = name;
    try {
      var map = new Map();
      for (var i = 0; i < EXAMPLE_FILES.length; i++) {
        var file = EXAMPLE_FILES[i];
        var url = '../examples/' + encodeURIComponent(name) + '/' + file;
        try {
          map.set(file, await fetchText(url));
        } catch (error) {
          if (file === 'plugin.json') { throw error; }
          addLog('warn', 'Optional example file missing: ' + file);
        }
      }
      applyFiles(map, 'example "' + name + '"');
    } catch (error) {
      setStatus('Could not load example. Use an HTTP server or Load folder.', 'error');
      addLog('error', 'Example load failed: ' + error.message);
      toast('Examples need an HTTP server. Run python -m http.server 8000 from the repo root.', 'error');
    }
  }

  async function loadFolder(fileList) {
    if (!fileList || !fileList.length) { return; }
    setStatus('Loading folder…');
    try {
      var map = new Map();
      for (var i = 0; i < fileList.length; i++) {
        var file = fileList[i];
        var relative = file.webkitRelativePath || file.name;
        var path = relative.indexOf('/') >= 0 ? relative.slice(relative.indexOf('/') + 1) : file.name;
        if (!TEXT_EXTENSIONS.test(path)) { continue; }
        map.set(path, await file.text());
      }
      applyFiles(map, 'folder');
    } catch (error) {
      setStatus('Folder load failed.', 'error');
      addLog('error', 'Folder load failed: ' + error.message);
      toast(error.message, 'error');
    }
  }

  function applyFiles(map, label) {
    var nextManifest = parseManifest(map);
    files = map;
    manifest = nextManifest;
    manifestId = nextManifest.id || null;
    currentEntry = nextManifest.entry;
    currentFile = files.has(currentEntry) ? currentEntry : sortedFiles()[0];
    storage = new Map();
    resetMockInputs(true);
    renderFileTabs();
    els.sourceEditor.value = files.get(currentFile) || '';
    updateHints();
    addLog('info', 'Loaded ' + label + ' (' + files.size + ' files)');
    runPreview();
  }

  function sortedFiles() {
    var names = Array.from(files.keys());
    var order = ['plugin.json', currentEntry, 'styles.css', 'common.js', 'script.js'];
    names.sort(function (a, b) {
      var ai = order.indexOf(a);
      var bi = order.indexOf(b);
      if (ai < 0) { ai = 100; }
      if (bi < 0) { bi = 100; }
      if (ai !== bi) { return ai - bi; }
      return a.localeCompare(b);
    });
    return names;
  }

  function renderFileTabs() {
    els.fileTabs.innerHTML = '';
    sortedFiles().forEach(function (name) {
      var button = document.createElement('button');
      button.className = 'file-tab' + (name === currentFile ? ' active' : '');
      button.textContent = name;
      button.addEventListener('click', function () {
        currentFile = name;
        els.sourceEditor.value = files.get(name) || '';
        renderFileTabs();
      });
      els.fileTabs.appendChild(button);
    });
    if (!files.has('plugin.json')) {
      var missing = document.createElement('span');
      missing.className = 'file-tab missing';
      missing.textContent = 'plugin.json missing';
      els.fileTabs.appendChild(missing);
    }
  }

  function updateHints() {
    var inputs = manifest && Array.isArray(manifest.inputs) ? manifest.inputs : [];
    var actions = manifest && Array.isArray(manifest.actions) ? manifest.actions : [];
    els.hintInputs.textContent = inputs.length ? inputs.join(', ') : 'app, time (always)';
    els.hintActions.textContent = actions.length ? actions.join(', ') : 'none declared';
  }

  function nowSnapshot() {
    var date = new Date();
    return {
      iso: date.toISOString(),
      epochMs: date.getTime(),
      utcOffsetMinutes: -date.getTimezoneOffset(),
      year: date.getFullYear(),
      month: date.getMonth() + 1,
      day: date.getDate(),
      hour: date.getHours(),
      minute: date.getMinutes(),
      second: date.getSeconds(),
      weekday: date.getDay() === 0 ? 7 : date.getDay()
    };
  }

  function defaultConfig() {
    var config = {};
    var settings = manifest && manifest.settings ? manifest.settings : {};
    Object.keys(settings).forEach(function (key) {
      config[key] = settings[key].default;
    });
    return config;
  }

  function defaultPlacement() {
    var placement = manifest && manifest.placement ? manifest.placement : DEFAULT_PLACEMENT;
    return {
      width: Number(placement.width) || DEFAULT_PLACEMENT.width,
      height: Number(placement.height) || DEFAULT_PLACEMENT.height
    };
  }

  function defaultState() {
    var inputs = manifest && Array.isArray(manifest.inputs) ? manifest.inputs : [];
    var placement = defaultPlacement();
    var state = {
      app: {
        version: '1.0.0',
        pluginApiVersion: 1,
        locale: 'en-US',
        timeZone: Intl.DateTimeFormat().resolvedOptions().timeZone || 'UTC',
        theme: 'dark',
        viewport: { width: placement.width, height: placement.height },
        safeArea: { top: 0, right: 0, bottom: 0, left: 0 },
        nightMode: false,
        enabled: true,
        visible: true
      },
      time: nowSnapshot()
    };

    if (inputs.indexOf('weather') >= 0) {
      state.weather = {
        temperature: 18.4,
        unit: 'celsius',
        code: 3,
        description: 'Overcast',
        locationLabel: 'Berlin',
        fetchedAt: new Date().toISOString()
      };
    }
    if (inputs.indexOf('playback') >= 0) {
      state.playback = {
        playing: true,
        index: 1,
        total: 5,
        intervalSeconds: 10,
        progress: 0.4,
        muted: false,
        slideshowRunning: true
      };
    }
    if (inputs.indexOf('media') >= 0) {
      state.media = {
        hasSession: true,
        title: 'Midnight City',
        artist: 'M83',
        album: 'Hurry Up, We\'re Dreaming',
        packageName: 'com.spotify.music',
        playing: true,
        canPrevious: true,
        canNext: true,
        positionSeconds: 42,
        durationSeconds: 244
      };
    }
    if (inputs.indexOf('image') >= 0) {
      state.image = {
        id: 'playground-image-1',
        type: 'photo',
        livePhoto: false,
        width: 1600,
        height: 1200,
        aspectBucket: 'fourThree',
        aspectLabel: '4:3',
        mimeType: 'image/jpeg',
        cached: true,
        exifDate: '2026-09-23T12:00:00.000Z',
        description: 'A quiet street in autumn',
        location: 'Razvilka, Moscow Oblast',
        tags: ['autumn', 'street', 'dog']
      };
    }
    if (inputs.indexOf('config') >= 0) {
      state.config = deepCopy(mockConfig);
    }
    if (inputs.indexOf('placement') >= 0) {
      state.placement = {
        anchor: 'bottom-end',
        x: 0.70,
        y: 0.66,
        width: placement.width,
        height: placement.height,
        zOrder: 10,
        showDuringNight: false
      };
    }
    return state;
  }

  function deepCopy(value) {
    return JSON.parse(JSON.stringify(value));
  }

  function resetMockInputs(silent) {
    silent = silent === true;
    mockConfig = defaultConfig();
    mockState = defaultState();
    mockPlacement = defaultPlacement();
    lastValidStateText = JSON.stringify(mockState, null, 2);
    lastValidConfigText = JSON.stringify(mockConfig, null, 2);
    els.stateEditor.value = lastValidStateText;
    els.configEditor.value = lastValidConfigText;
    els.inputStatus.textContent = 'Mock reset from manifest.';
    if (!silent) {
      addLog('info', 'Reset mock inputs from manifest defaults');
      sendState();
      sendConfig();
    }
  }

  function applyInputs() {
    var stateText = els.stateEditor.value;
    var configText = els.configEditor.value;
    var stateError = null;
    var configError = null;
    var nextState = mockState;
    var nextConfig = mockConfig;

    try {
      nextState = parseJson(stateText, 'Mock state');
      if (!nextState || typeof nextState !== 'object' || Array.isArray(nextState)) {
        throw new Error('Mock state must be a JSON object.');
      }
    } catch (error) {
      stateError = error.message;
    }
    try {
      nextConfig = parseJson(configText, 'Mock config');
      if (!nextConfig || typeof nextConfig !== 'object' || Array.isArray(nextConfig)) {
        throw new Error('Mock config must be a JSON object.');
      }
    } catch (error) {
      configError = error.message;
    }

    var applied = [];
    if (!stateError) {
      mockState = nextState;
      lastValidStateText = stateText;
      applied.push('state');
    }
    if (!configError) {
      mockConfig = nextConfig;
      lastValidConfigText = configText;
      applied.push('config');
    }
    if (applied.length) {
      els.inputStatus.textContent = 'Applied ' + applied.join(' and ') + '.';
      addLog('info', 'Applied mock ' + applied.join(' and '), {
        state: applied.indexOf('state') >= 0 ? mockState : undefined,
        config: applied.indexOf('config') >= 0 ? mockConfig : undefined
      });
      sendState();
      sendConfig();
    } else {
      els.inputStatus.textContent = 'Nothing applied; fix the JSON errors.';
    }
    if (stateError) {
      addLog('error', stateError);
      toast(stateError, 'error');
      els.stateEditor.value = lastValidStateText;
    }
    if (configError) {
      addLog('error', configError);
      toast(configError, 'error');
      els.configEditor.value = lastValidConfigText;
    }
  }

  function buildConsoleBridge() {
    return [
      '(function () {',
      "  'use strict';",
      '  function fmt(value) {',
      '    if (typeof value === "string") { return value; }',
      '    if (value instanceof Error) { return value.stack || value.message; }',
      '    try { return JSON.stringify(value); } catch (error) { return String(value); }',
      '  }',
      '  function send(level, args) {',
      '    try {',
      '      var text = Array.prototype.map.call(args, fmt).join(" ");',
      "      parent.postMessage({type: 'playground-console', payload: {level: level, message: text}}, '*');",
      '    } catch (error) {}',
      '  }',
      "  ['log', 'info', 'warn', 'error', 'debug'].forEach(function (level) {",
      '    var original = console[level];',
      '    console[level] = function () {',
      '      send(level, arguments);',
      '      if (original) { original.apply(console, arguments); }',
      '    };',
      '  });',
      '  window.addEventListener("error", function (event) {',
      '    send("error", [event.message + (event.filename ? " (" + event.filename + ":" + event.lineno + ")" : "")]);',
      '  });',
      '  window.addEventListener("unhandledrejection", function (event) {',
      '    var reason = event.reason && (event.reason.stack || event.reason.message) || event.reason;',
      '    send("error", ["Unhandled promise rejection: " + fmt(reason)]);',
      '  });',
      '})();'
    ].join('\n');
  }

  function safeScript(text) {
    return String(text).replace(/<\/script/gi, '<\\/script');
  }

  function safeStyle(text) {
    return String(text).replace(/<\/style/gi, '<\\/style');
  }

  function resolveLocalPath(ref) {
    if (!ref) { return null; }
    var raw = ref.trim();
    if (!raw || raw.charAt(0) === '#' ||
        /^(?:[a-z][a-z0-9+.-]*:|\/\/)/i.test(raw)) {
      return null;
    }
    raw = raw.split('#')[0].split('?')[0];
    if (raw.charAt(0) === '/') { raw = raw.slice(1); }
    var base = currentEntry.indexOf('/') >= 0
      ? currentEntry.slice(0, currentEntry.lastIndexOf('/') + 1)
      : '';
    var parts = (base + raw).split('/');
    var out = [];
    for (var i = 0; i < parts.length; i++) {
      var part = parts[i];
      if (!part || part === '.') { continue; }
      if (part === '..') { out.pop(); continue; }
      out.push(part);
    }
    return out.join('/');
  }

  function injectSources(doc) {
    var missing = [];
    Array.prototype.slice.call(doc.querySelectorAll('link[rel~="stylesheet"]')).forEach(function (link) {
      var path = resolveLocalPath(link.getAttribute('href'));
      if (!path || !files.has(path)) {
        missing.push(link.getAttribute('href'));
        link.parentNode.removeChild(link);
        return;
      }
      var style = doc.createElement('style');
      style.textContent = safeStyle(files.get(path));
      link.parentNode.replaceChild(style, link);
    });
    Array.prototype.slice.call(doc.querySelectorAll('script[src]')).forEach(function (script) {
      var path = resolveLocalPath(script.getAttribute('src'));
      if (!path || !files.has(path)) {
        missing.push(script.getAttribute('src'));
        script.parentNode.removeChild(script);
        return;
      }
      var inline = doc.createElement('script');
      if (script.getAttribute('type')) { inline.setAttribute('type', script.getAttribute('type')); }
      inline.textContent = safeScript(files.get(path));
      script.parentNode.replaceChild(inline, script);
    });
    if (missing.length) {
      addLog('warn', 'Removed unresolved local assets: ' + missing.join(', '));
    }
  }

  function buildSrcdoc() {
    var entryHtml = files.get(currentEntry);
    var doc = new DOMParser().parseFromString(entryHtml, 'text/html');
    if (!doc.head) {
      doc.documentElement.insertBefore(doc.createElement('head'), doc.body);
    }
    injectSources(doc);
    var bootstrap = doc.createElement('script');
    bootstrap.textContent = buildConsoleBridge() + '\n' + safeScript(sdkSource);
    doc.head.insertBefore(bootstrap, doc.head.firstChild);
    return '<!doctype html>\n' + doc.documentElement.outerHTML;
  }

  function runPreview() {
    window.clearTimeout(runTimer);
    var nextManifest;
    try {
      nextManifest = parseManifest(files);
    } catch (error) {
      setStatus('Cannot run: ' + error.message, 'error');
      addLog('error', error.message);
      return;
    }
    manifest = nextManifest;
    manifestId = nextManifest.id || null;
    currentEntry = nextManifest.entry;
    mockPlacement = defaultPlacement();
    updateHints();
    if (!els.stateEditor.value.trim()) { resetMockInputs(true); }
    if (!els.configEditor.value.trim()) { resetMockInputs(true); }

    var srcdoc;
    try {
      srcdoc = buildSrcdoc();
    } catch (error) {
      setStatus('Preview build failed: ' + error.message, 'error');
      addLog('error', 'Preview build failed: ' + error.message);
      return;
    }

    if (iframe) {
      iframe.remove();
    }
    iframe = document.createElement('iframe');
    iframe.id = 'preview-frame';
    iframe.title = 'Plugin preview';
    iframe.setAttribute('sandbox', 'allow-scripts');
    iframe.addEventListener('load', function () {
      addLog('debug', 'Preview loaded: ' + currentEntry);
      fitPreview();
    });
    iframe.addEventListener('error', function () {
      addLog('error', 'The preview iframe failed to load.');
      setStatus('Preview iframe failed.', 'error');
    });
    els.previewEmpty.hidden = true;
    els.previewShell.hidden = false;
    els.previewShell.appendChild(iframe);
    iframe.srcdoc = srcdoc;
    fitPreview();
    setStatus('Running ' + (manifest.name || 'plugin'), 'ok');
    addLog('info', 'Preview reloaded from ' + currentEntry + ' (' + files.size + ' files)');
  }

  function fitPreview() {
    if (!els.previewSurface || !iframe) { return; }
    var placement = mockPlacement;
    var width = Math.max(1, Number(placement.width) || DEFAULT_PLACEMENT.width);
    var height = Math.max(1, Number(placement.height) || DEFAULT_PLACEMENT.height);
    var availableWidth = Math.max(40, els.previewSurface.clientWidth - 44);
    var availableHeight = Math.max(40, els.previewSurface.clientHeight - 44);
    var scale = Math.min(1, availableWidth / width, availableHeight / height);
    scale = Math.max(0.1, scale);
    els.previewShell.style.width = Math.round(width * scale) + 'px';
    els.previewShell.style.height = Math.round(height * scale) + 'px';
    iframe.style.width = width + 'px';
    iframe.style.height = height + 'px';
    iframe.style.transform = 'scale(' + scale + ')';
    els.previewDims.textContent = width + ' × ' + height + ' · ' +
      Math.round(scale * 100) + '%';
  }

  function postToPreview(type, payload, id) {
    if (!iframe || !iframe.contentWindow) { return; }
    var message = { type: type, payload: payload === undefined ? null : payload };
    if (id) { message.id = id; }
    iframe.contentWindow.postMessage(message, '*');
  }

  function sendState(id) {
    postToPreview('state', mockState, id);
  }

  function sendConfig(id) {
    postToPreview('config', mockConfig, id);
  }

  function sendError(message, id, code) {
    postToPreview('error', { message: message, code: code || null }, id);
  }

  function onWindowMessage(event) {
    if (!iframe || event.source !== iframe.contentWindow) { return; }
    var message = event.data;
    if (!message || typeof message !== 'object' || typeof message.type !== 'string') { return; }
    var payload = message.payload || {};
    var id = message.id;

    switch (message.type) {
      case 'playground-console':
        addLog(payload.level || 'info', payload.message || '');
        return;
      case 'ready':
        addLog('debug', 'SDK ready');
        sendState();
        sendConfig();
        return;
      case 'getState':
      case 'requestUpdate':
        sendState(id);
        return;
      case 'getConfig':
        sendConfig(id);
        return;
      case 'requestPlacement':
        handlePlacement(payload, id);
        return;
      case 'action':
        handleAction(payload, id);
        return;
      case 'openLink':
        addLog('info', 'openLink request: ' + (payload.url || ''));
        postToPreview('actionResult', {
          action: 'openLink', ok: true, result: null, error: null
        }, id);
        return;
      case 'storage.get':
        handleStorageGet(payload, id);
        return;
      case 'storage.set':
        handleStorageSet(payload, id);
        return;
      case 'storage.remove':
        handleStorageRemove(payload, id);
        return;
      case 'storage.clear':
        storage.clear();
        addLog('debug', 'storage.clear');
        postToPreview('storageResult', { ok: true, key: null, value: null, error: null }, id);
        return;
      case 'network.request':
        addLog('warn', 'network.request denied: ' + (payload.url || ''), payload);
        postToPreview('networkResult', {
          ok: false, status: null, headers: null, body: null,
          error: 'Network is disabled in the playground.'
        }, id);
        return;
      case 'log':
        addLog(payload.level || 'info', payload.message || '');
        return;
      case 'reportError':
        addLog('error', payload.message || 'Plugin reported an error', payload.details);
        return;
      default:
        addLog('warn', 'Unsupported bridge message: ' + message.type);
        sendError('Unsupported bridge message: ' + message.type, id, 'unsupported_type');
    }
  }

  function handleAction(payload, id) {
    var name = payload.name || '';
    var actionPayload = payload.payload || {};
    var declared = manifest && Array.isArray(manifest.actions)
      ? manifest.actions.indexOf(name) >= 0
      : false;
    addLog('action', 'action ' + name + (declared ? '' : ' (not declared)'), actionPayload);
    postToPreview('actionResult', {
      action: name, ok: true, result: null, error: null
    }, id);
  }

  function handlePlacement(payload, id) {
    var width = Number(payload.width);
    var height = Number(payload.height);
    if (!isFinite(width) || !isFinite(height) || width <= 0 || height <= 0) {
      sendError('Placement width and height must be positive numbers.', id, 'invalid_placement');
      return;
    }
    mockPlacement = { width: width, height: height };
    fitPreview();
    addLog('debug', 'requestPlacement ' + Math.round(width) + '×' + Math.round(height));
    postToPreview('placement', {
      anchor: payload.anchor || 'top-start',
      x: payload.x,
      y: payload.y,
      width: width,
      height: height,
      zOrder: payload.zOrder || 0,
      showDuringNight: Boolean(payload.showDuringNight)
    }, id);
  }

  function storageKey(payload, id) {
    var key = payload.key;
    if (typeof key !== 'string' || !key) {
      postToPreview('storageResult', {
        ok: false, key: null, value: null, error: 'Storage key is required.'
      }, id);
      return null;
    }
    return key;
  }

  function handleStorageGet(payload, id) {
    var key = storageKey(payload, id);
    if (key === null) { return; }
    var value = storage.has(key) ? storage.get(key) : null;
    addLog('debug', 'storage.get ' + key);
    postToPreview('storageResult', { ok: true, key: key, value: value, error: null }, id);
  }

  function handleStorageSet(payload, id) {
    var key = storageKey(payload, id);
    if (key === null) { return; }
    var raw = payload.value;
    var value = typeof raw === 'string' ? raw : JSON.stringify(raw);
    storage.set(key, value);
    addLog('debug', 'storage.set ' + key + ' = ' + value);
    postToPreview('storageResult', { ok: true, key: key, value: value, error: null }, id);
  }

  function handleStorageRemove(payload, id) {
    var key = storageKey(payload, id);
    if (key === null) { return; }
    storage.delete(key);
    addLog('debug', 'storage.remove ' + key);
    postToPreview('storageResult', { ok: true, key: key, value: null, error: null }, id);
  }

  document.addEventListener('DOMContentLoaded', init);
})();
