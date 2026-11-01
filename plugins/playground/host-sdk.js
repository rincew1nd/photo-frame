// Injected plugin SDK for the playground iframe.
// This file only exposes its own source so the playground can inject the SDK
// into a sandboxed srcdoc iframe without fetching (works from file://).
(function () {
  'use strict';

  function hostSdk() {
    'use strict';
    var seq = 0;
    var pending = {};
    var stateListeners = [];
    var eventListeners = [];
    var lastState = null;
    var lastConfig = {};
    var resolveReady;
    var ready = new Promise(function (resolve) { resolveReady = resolve; });

    function send(type, payload, callback) {
      var id = 'p' + (++seq);
      if (callback) { pending[id] = callback; }
      parent.postMessage({type: type, id: id, payload: payload || {}}, '*');
      return id;
    }

    function request(type, payload) {
      return new Promise(function (resolve, reject) {
        send(type, payload, function (message) {
          if (message.type === 'error') {
            reject(new Error((message.payload && message.payload.message) || 'Plugin host error'));
          } else {
            resolve(message.payload);
          }
        });
      });
    }

    window.addEventListener('message', function (event) {
      if (event.source !== window.parent) { return; }
      var message = event.data;
      if (!message || typeof message !== 'object') { return; }
      if (message.id && pending[message.id]) {
        var callback = pending[message.id];
        delete pending[message.id];
        callback(message);
      }
      if (message.type === 'state') {
        lastState = message.payload;
        if (resolveReady) { resolveReady(lastState); resolveReady = null; }
        for (var i = 0; i < stateListeners.length; i++) {
          try { stateListeners[i](lastState); } catch (error) { console.error(error); }
        }
      } else if (message.type === 'event') {
        for (var j = 0; j < eventListeners.length; j++) {
          try { eventListeners[j](message.payload); } catch (error) { console.error(error); }
        }
      } else if (message.type === 'config') {
        lastConfig = message.payload || {};
      }
    });

    window.host = {
      ready: ready,
      getState: function () {
        return lastState ? Promise.resolve(lastState) : request('getState');
      },
      onState: function (callback) {
        if (typeof callback !== 'function') { return; }
        stateListeners.push(callback);
        if (lastState) { callback(lastState); }
      },
      onEvent: function (callback) {
        if (typeof callback === 'function') { eventListeners.push(callback); }
      },
      getConfig: function () {
        return request('getConfig');
      },
      requestUpdate: function () {
        return request('requestUpdate');
      },
      requestPlacement: function (placement) {
        return request('requestPlacement', placement);
      },
      action: function (name, payload) {
        return request('action', {name: name, payload: payload || {}});
      },
      openLink: function (url) {
        return request('openLink', {url: url});
      },
      storage: {
        get: function (key) { return request('storage.get', {key: key}); },
        set: function (key, value) { return request('storage.set', {key: key, value: value}); },
        remove: function (key) { return request('storage.remove', {key: key}); },
        clear: function () { return request('storage.clear'); }
      },
      network: {
        request: function (options) { return request('network.request', options); }
      },
      log: function (level, message) {
        parent.postMessage({type: 'log', payload: {level: level, message: message}}, '*');
      },
      reportError: function (message, details) {
        parent.postMessage({type: 'reportError', payload: {message: message, details: details}}, '*');
      }
    };

    parent.postMessage({type: 'ready'}, '*');
  }

  window.__PHOTOFRAME_HOST_SDK_SOURCE = '(' + hostSdk.toString() + ')();';
})();
