# Plugin Author Guide

## Bundle

A plugin is a ZIP whose root contains `plugin.json` and `index.html`. CSS,
JavaScript, assets, an icon, and screenshots are optional. One top-level folder
is allowed; the host normalizes it. The limits are 20 MB compressed, 100 MB
extracted, and 500 files.

```
clock.zip
  plugin.json
  index.html
  styles.css
  script.js
  icon.png
  screenshots/clock.png
```

The host rejects traversal, symlinks, native binaries, remote code, missing
entries, duplicate IDs, and unsupported API versions. A SHA-256 is recorded.

## Manifest

```json
{
  "id": "com.example.clock",
  "name": "Clock",
  "version": "1.0.0",
  "apiVersion": 1,
  "minAppVersion": "1.0.0",
  "author": "Example Author",
  "license": "MIT",
  "description": "A clock overlay.",
  "entry": "index.html",
  "icon": "icon.png",
  "screenshots": ["screenshots/clock.png"],
  "permissions": { "network": false },
  "inputs": ["time", "config"],
  "actions": ["next", "pause"],
  "placement": {
    "anchor": "top-start",
    "x": 0.05,
    "y": 0.05,
    "width": 320,
    "height": 160,
    "zOrder": 10,
    "showDuringNight": false
  },
  "settings": {
    "format": {
      "type": "select",
      "label": "Time format",
      "default": "24h",
      "options": [
        { "value": "24h", "label": "24-hour" },
        { "value": "12h", "label": "12-hour" }
      ]
    },
    "color": { "type": "color", "label": "Text color", "default": "#FFFFFFFF" }
  }
}
```

`inputs` declares snapshot sections: `time`, `weather`, `playback`, `media`,
`image`, `config`, `placement`. `app` and `time` are always sent. Declare only
what you need; undeclared sections are absent, so no library or credential data
leaks.

Settings types: `text`, `multiline`, `number`, `boolean`, `select`, `color`,
and `url`. Use `number` with `min`/`max` for opacity or other bounded values.
The app renders these fields in the plugin's own settings screen. The bundled
examples share `backgroundColor` (`#000000`), `backgroundOpacity` (`0.8`), and
`cornerRadius` (`2em`); reuse them to match the default card style.

## Host API (v1)

The host injects a small SDK. Wait for `host.ready`, then read state or
subscribe:

```js
host.ready.then((state) => render(state));

host.onState((state) => {
  document.getElementById('clock').textContent = state.time.iso;
});

host.onEvent((event) => {
  // imageChange, playbackChange, settingsChange, viewportChange
});
```

Available calls:

```js
host.getState()
host.getConfig()
host.requestUpdate()
host.requestPlacement({x, y, width, height, anchor, durationMs})
host.action('next', {})
host.openLink('https://example.com')
host.storage.get(key)
host.storage.set(key, jsonString)
host.storage.remove(key)
host.storage.clear()
host.network.request({url, method, headers, body})
host.log(level, message)
host.reportError(message, details)
```

Promise-based calls resolve with the host response. Unknown or malformed
messages are ignored. The bridge and snapshot are versioned (`apiVersion: 1`).

State sections include:

- `app` and `time` (always);
- `weather` when declared and configured;
- `playback` (playing, index, total, interval, progress, muted);
- `media` (background session): `hasSession`, `title`, `artist`, `album`,
  `packageName`, `playing`, `canPrevious`, `canNext`, `positionSeconds`,
  `durationSeconds`; null when no session exists;
- `image` (ID, type, dimensions, aspect, MIME, cached, date, description,
  location, tags);
- `config` and `placement` when declared.

### Background media

Declare the `media` input and the media actions, then render defensively:

```json
{
  "inputs": ["media", "config"],
  "actions": ["mediaPrevious", "mediaPlayPause", "mediaNext"]
}
```

```js
host.onState((state) => {
  const media = state.media;
  if (!media || !media.hasSession) {
    document.getElementById('track').textContent = 'No media session';
    return;
  }
  document.getElementById('track').textContent =
    media.title + ' — ' + media.artist + (media.playing ? ' (playing)' : '');
});

host.action('mediaPlayPause');
host.action('mediaPrevious');
host.action('mediaNext');
```

`mediaNext` / `mediaPrevious` / `mediaPlayPause` control the background media
session. The slideshow actions remain `next`, `previous`, and `togglePause`.
On Android, these require Notification access, granted in
**Settings → Plugins → plugin with the `media` input → Background media →
Notification access**. Without access `media` is null; always handle that case.

## Rules and limits

- Plugins never receive the Immich API key, server URL, credentials, album
  lists, file paths, or unrelated metadata.
- Direct `fetch`, remote images/fonts, cookies, `localStorage`, and host file
  access are blocked. Network is denied unless the user grants the Network
  permission; granted requests go through the host proxy.
- Actions must be declared, granted by the user, and are rate-limited (default
  10/minute). They run only while the slideshow is visible.
- Plugin storage is namespaced per instance, limited to 1 MB, and removed on
  uninstall.
- Load timeout is 10 seconds. Three failures within five minutes disable the
  plugin. A failed plugin is hidden.
- External links open in the system browser after confirmation. `file:`,
  `javascript:`, `intent:`, `data:`, popups, and in-app navigation are blocked.

## Example plugins

The app ships clock, weather, metadata, calendar, playback, and image-info
examples. Their ZIPs are the best starting point; unzip one, change the
manifest ID, and replace the HTML/CSS/JS. The clock/weather/metadata examples
start enabled on first run; the others start disabled.
