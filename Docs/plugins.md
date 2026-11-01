# Plugin System

Status: Draft v0.3 (design target; Phase 4 not started)
Related: [`architecture.md`](architecture.md), [`security.md`](security.md),
[`requirements-alignment.md`](requirements-alignment.md)

> Implementation status (2026-11-01): this document is the Phase 4 design target, not current
> behavior. The app currently ships clock/weather/metadata overlays as compiled Flutter widgets and a
> placeholder Plugins settings screen; the target is for all three to become bundled plugins. No
> plugin code, webview dependency, registry, host, bridge, or reference plugin exists. Phase 0's
> transparent-overlay gate is unresolved: `webview_cef` 0.6.2 has no transparency API, and the
> available Android WebView is below the Chromium 100+ baseline.

## 1. Model

A plugin is a self-contained ZIP bundle containing:

- a JSON manifest;
- an HTML document;
- a CSS stylesheet;
- optional sandboxed JavaScript;
- optional local assets;
- optional screenshots and an icon for the list/install UI.

Plugins render as transparent, interactive overlays above the current photo/video and below the
app controls and dialogs. They receive a read-only application state snapshot and may expose
settings, invoke approved actions, request network access, and request placement changes.

Every overlay is a plugin in v1, including clock, weather, and metadata. Those three are bundled
with the app and enabled by default; no compiled-in overlay remains after migration.

Plugins never receive the Immich API key, server URL, credentials, album lists, or arbitrary app
storage. Plugins never call Immich directly.

### Why HTML/CSS/JS, not Dart

Runtime-installed Dart cannot be safely sandboxed: Flutter has no supported dynamic-code sandbox,
and arbitrary Dart would run inside the host process with access to app storage and credentials.
Compiling each plugin ahead of time would require a build step, a signature/trust model, and native
toolchains per platform — none of which fit local ZIP installation. Sandboxed HTML/CSS/JS inside the
per-instance webview keeps the security boundary the rest of this design already relies on. A
declarative JSON-only UI is the safer fallback if scripting proves too risky, but it cannot express
live clocks, animation, or arbitrary event handling as cleanly.

## 2. Bundle layout

```
clock.zip
  plugin.json
  index.html
  styles.css
  script.js
  assets/
    ...
  icon.png
  screenshots/
    clock.png
```

A ZIP may also contain a single top-level folder; the host normalises the path. Required files:
`plugin.json` and the entry document. Assets, icon, and screenshots must be inside the bundle.

Rules:

- No symlinks, device files, absolute paths, `..` traversal, or zip bombs.
- No native binaries, executables, or remote code includes.
- HTML/CSS/JS assets must be local; external network is host-mediated.
- The entry file must be inside the extracted bundle.
- Icon and screenshots must be local PNG, JPEG, or WebP within size limits.
- ZIP limits: 20 MB compressed, 100 MB extracted, 500 files (defaults; configurable).

## 3. Manifest

Example `plugin.json`:

```json
{
  "id": "com.example.clock",
  "name": "Clock",
  "version": "1.0.0",
  "apiVersion": 1,
  "minAppVersion": "1.0.0",
  "author": "Example Author",
  "license": "MIT",
  "description": "A configurable clock overlay for the photo frame.",
  "homepage": "https://example.com/clock",
  "entry": "index.html",
  "icon": "icon.png",
  "screenshots": ["screenshots/clock.png"],
  "permissions": {
    "network": false
  },
  "inputs": ["time", "config"],
  "actions": ["next", "pause"],
  "updateTriggers": ["timeTick", "imageChange", "playbackChange"],
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
      ],
      "help": "Choose the clock format."
    },
    "showSeconds": {
      "type": "boolean",
      "label": "Show seconds",
      "default": false
    },
    "color": {
      "type": "color",
      "label": "Text color",
      "default": "#FFFFFFFF"
    },
    "backgroundOpacity": {
      "type": "number",
      "label": "Background opacity",
      "default": 0.4,
      "min": 0,
      "max": 1,
      "step": 0.05
    }
  }
}
```

### Fields

| Field | Required | Meaning |
|---|---|---|
| `id` | yes | Stable reverse-DNS identifier; unique across installed plugins |
| `name` | yes | Display name |
| `version` | yes | Semantic version |
| `apiVersion` | yes | Plugin API version the plugin targets |
| `minAppVersion` | no | Minimum host app version |
| `author` | yes | Display name of the author |
| `license` | yes | SPDX-like license identifier or text reference |
| `description` | yes | Short description shown in install/details UI |
| `homepage` | no | Informational URL |
| `entry` | yes | Entry HTML file inside the bundle |
| `icon` | no | Relative image path shown in the plugin list and install/details UI |
| `screenshots` | no | Relative image paths shown in the install/details UI |
| `permissions` | yes | Capability declarations (currently `network`) |
| `inputs` | no | Snapshot sections the plugin needs: `app`, `time`, `weather`, `playback`, `image`, `config`, `placement`; app/time are always sent |
| `actions` | no | App actions the plugin may request |
| `updateTriggers` | no | Declared event needs; the host still pushes required minimums |
| `placement` | no | Default position, size, z-order, night-mode visibility |
| `settings` | no | JSON settings schema |

### Placement

- `anchor`: `top|center|bottom` x `start|center|end`; used as the initial/default placement.
- `x`, `y`: normalised coordinates (0..1) within the safe area; updated by drag-and-drop.
- `width`, `height`: logical pixels; editable by resizing, clamped to the viewport.
- `zOrder`: integer; higher is closer to the viewer. App controls/dialogs always remain above.
- `showDuringNight`: default `false`.

The host validates placement against the viewport and safe-area insets and persists the final
values. Placement can be edited directly over the slideshow in an edit mode and from the plugin's
settings screen, with drag and edge/corner resize handles. The Plugins screen has an optional
snap-to-grid toggle and a configurable grid size (logical pixels). Grid settings persist globally;
per-plugin position and size persist per instance.

### Settings schema

Supported field types:

| Type | Extra fields |
|---|---|
| `text` | `default`, `label`, `help`, `maxLength`, `pattern` |
| `multiline` | as text, with rows |
| `number` | `min`, `max`, `step`, `default` |
| `boolean` | `default` |
| `select` | `options[{value,label}]`, `default` |
| `color` | `default` (`#RRGGBB` or `#AARRGGBB`) |
| `url` | `default`, `pattern`; URL validation |

The app renders the settings UI from the schema in the plugin's dedicated screen (Plugins → plugin
→ settings), validates before applying, and sends the updated configuration to the plugin
immediately. Configuration is stored per plugin instance and is read-only to the plugin. The same
screen also exposes enable/disable, update, uninstall, permissions, requested inputs, and the
placement editor.

## 4. Installation and lifecycle

### Install

1. User selects a ZIP file.
2. Extract to a temporary directory.
3. Validate ZIP structure, manifest JSON, API compatibility, duplicate ID, file limits, icon and
   screenshot types, declared inputs, and entry existence.
4. Compute and store a SHA-256 hash.
5. Show identity: name, ID, version, author, license, description, icon, screenshots, requested
   permissions, requested inputs, and app/API compatibility.
6. User explicitly installs/enables.
7. Move the bundle atomically into the plugin store.
8. Register the plugin and apply the default placement.
9. Start the overlay if the slideshow is visible.

No plugin is installed silently. A failed validation leaves no partial installation.

### Update

- Import a ZIP with the same ID and a newer version.
- Show the new identity, version, description, icon, screenshots, requested inputs, and permission
  changes.
- Preserve configuration and placement when the settings schema is compatible.
- If the schema is incompatible, show a confirmation and require explicit acceptance.
- Install atomically; keep the previous version if the update fails.
- Downgrades require explicit confirmation or are rejected.

### Enable/disable

- Disabling removes the overlay immediately and frees its webview.
- Files, configuration, and storage remain.
- Enabling recreates the overlay and restores placement/configuration.

### Uninstall

- Remove the overlay and webview.
- Remove the bundle, configuration, placement, and plugin-scoped storage.
- Remove the registry entry.
- Log the action without exposing secrets.

### Inspect

The plugin list shows each plugin's icon, name, version, and enabled state. Opening a plugin goes to
its dedicated settings screen, which shows:

- name, ID, version, author, license, description, icon, screenshots;
- API compatibility;
- permissions, requested inputs, and action grants;
- schema-rendered settings;
- placement editor (drag, resize, grid snap/grid size);
- enable/disable, update, uninstall;
- recent errors/logs for that plugin.

## 5. Rendering host

### Per-instance transparent webview

- One transparent webview per plugin instance.
- Desktop: CEF via `webview_cef`, rendered offscreen into a Flutter texture. Phase 0 found that
  `webview_cef` 0.6.2 exposes no transparency/background API; a CEF/OSR transparency patch or an
  alternative must be proven before production host work.
- Android: system WebView via `webview_flutter`. Validate on Chromium 100+; the Phase 0 reference
  WebView was below baseline and rendered plugin HTML blank.
- The webview is sized to the plugin box, not the full screen. Clicks outside the box reach Flutter.
- App controls/dialogs are Flutter widgets above the plugin layer.
- Android fallback: if platform-view z-order prevents Flutter controls from appearing above
  webviews, the host hides plugin webviews while controls/dialogs are open and restores them after.

### Sandbox

- A trusted host page is served from the app’s loopback server.
- The plugin document runs in a sandboxed iframe (`sandbox="allow-scripts"`, no
  `allow-same-origin`), giving it an opaque origin with no host storage/cookie access.
- Plugin assets are served from the loopback server with a per-instance path/token.
- The host page and plugin communicate only through a validated `postMessage` bridge.
- No plugin access to Flutter, native APIs, filesystem, secure storage, or other plugins.
- CSP is applied to plugin responses and enforced at the webview request layer.

### Loopback server

- Binds to `127.0.0.1` on an ephemeral port.
- Uses a random per-session token in the path.
- Serves only the host page and the current plugin’s files.
- No directory listing, no traversal, no symlinks, no arbitrary file serving.
- CORS is limited to the host page/plugin assets.
- Shuts down or becomes unreachable when the app exits.
- Never exposes Immich credentials.

### Placement

- The host owns the box: anchor, coordinates, size, z-order, visibility.
- The plugin may call `host.requestPlacement({x,y,width,height,anchor,durationMs})`.
- The host clamps to the viewport and safe areas, animates if requested, persists, and updates the
  webview bounds.
- Plugins cannot draw outside their box.
- The user edits placement directly over the slideshow in edit mode or from the plugin's settings
  screen: drag to move, edge/corner handles to resize, optional grid snap, and a configurable grid
  size. Grid settings persist globally.
- Placement is stored as normalized x/y plus logical width/height and clamped after rotation or
  viewport changes.
- Plugins are hidden during night mode by default; `showDuringNight` is a per-instance option.

### Input and links

- Buttons, links, and form controls are handled by the webview and receive normal browser input.
- Text input uses the platform keyboard/IME where available.
- External links:
  - `http`/`https` are intercepted and opened in the system browser after confirmation.
  - `file:`, `javascript:`, `intent:`, `data:` navigation, popups, and in-app navigation are
    blocked.
  - Plugins can request a link through `host.openLink(url)`; the host applies the same policy.
- Plugin actions are invoked through the host bridge; they never call Immich directly.

### State delivery

- The host pushes a read-only snapshot filtered by the manifest's `inputs`; `app` and `time` are
  always sent:
  - app/plugin API version, locale, time zone, theme, viewport, safe-area insets, night mode;
  - current time/date;
  - weather (or null), fetched when the plugin declares `weather`;
  - playback state, index, total, interval, elapsed progress, mute, slideshow running;
  - current image metadata (ID, type, Live Photo, dimensions, aspect bucket, MIME, cached/offline,
    EXIF date, description, location, tags);
  - plugin configuration and placement.
- Calendar data: current date/time is always available. Event feeds are plugin-fetched and out of
  scope for app-provided data.
- Minimum cadence: at most 1 Hz time tick while the slideshow is visible.
- Immediate updates: image change, playback state change, weather refresh, settings change,
  viewport/orientation change, plugin enable/install.
- No polling is required. A plugin may request a refresh; the host applies the 1 Hz limit.
- Updates pause while the screen is off, the app is backgrounded, the plugin is hidden, or the
  slideshow is not visible.
- Updates are coalesced; a slow plugin cannot stall the slideshow.
- Plugins never receive credentials, server URL, API key, album lists, or unrelated library
  metadata.

## 6. Plugin JavaScript API (v1)

The bridge is versioned and validated. Proposed surface:

```js
host.ready                       // promise/event when the bridge is ready
host.getState()                  // latest read-only snapshot
host.onState(callback)           // full snapshot on state/time events
host.onEvent(callback)           // image/playback/settings/viewport events
host.getConfig()                 // current settings values
host.requestUpdate()             // optional; subject to 1 Hz limit
host.requestPlacement({x,y,width,height,anchor,durationMs})
host.action(name, payload)       // declared + granted actions only
host.openLink(url)               // external browser with confirmation
host.storage.get(key)
host.storage.set(key, value)
host.storage.remove(key)
host.storage.clear()
host.network.request({url, method, headers, body}) // if network permission granted
host.log(level, message)
host.reportError(message, details)
```

Rules:

- All messages are JSON, size-bounded, and validated.
- `getState` contains only the declared `inputs` plus mandatory app/time data.
- The host ignores unknown actions and malformed messages.
- Action calls are rate-limited (default 10 per minute; configurable).
- Storage is namespaced per instance; default quota 1 MB.
- Network is proxied by the host; no direct `fetch` is allowed.
- The plugin cannot change its own permissions, app settings, credentials, or other plugins.

## 7. Actions

Supported actions:

- `next`
- `previous`
- `pause`
- `resume`
- `togglePause`
- `mute`
- `unmute`
- `toggleMute`
- `openSettings`
- `openMediaSelection`

Actions must be declared in the manifest and granted by the user. They are rate-limited and only
run while the slideshow is visible and the plugin is enabled. They cannot modify server
configuration, credentials, permissions, or plugin configuration.

## 8. Network

- Denied by default.
- User grants the Network permission explicitly during install or later.
- Direct plugin network requests are blocked by CSP and native request interception.
- Granted network requests go through the host proxy:
  - HTTP/HTTPS only;
  - no API key or Immich credentials attached;
  - timeouts, response-size limits, and rate limits;
  - request/response data returned to the plugin.
- Remote images/fonts are not automatically allowed; plugins should bundle local assets. A future
  version may add domain allowlists and proxied remote subresources. Remote assets must fail
  gracefully.
- Domain restrictions are MAY; v1 uses permission-wide host proxying without an allowlist.
- Plugins cannot reach the Immich API, local app endpoints, or secure storage.

## 9. Storage

- Host-managed key/value store per plugin instance.
- Values are JSON-serializable; size-limited.
- Removed on uninstall; preserved on disable/update where compatible.
- Browser storage is unavailable because the plugin iframe has an opaque origin.
- Plugin configuration is read-only to the plugin; changes come through the host settings UI.

## 10. Permissions and consent

The install/details UI discloses:

- Network access;
- requested actions;
- requested snapshot inputs;
- storage use;
- icon, description, screenshots, author, version, license, and compatibility.

The user can revoke network/actions later. Revocation takes effect immediately. Plugins that fail
due to revoked permissions must handle the error gracefully.

## 11. Failure, limits, and lifecycle

- Load timeout: 10 seconds.
- Repeated failures (default 3 within 5 minutes) disable the plugin and log the reason.
- A failed plugin is hidden; it must not cover or block the slideshow.
- Plugin webviews are disposed when disabled, uninstalled, or when the slideshow is not visible.
- Hidden plugins receive no time ticks or state updates.
- Limits:
  - 20 MB ZIP, 100 MB extracted, 500 files;
  - 20 installed plugins;
  - 10 active/visible instances;
  - one instance per plugin in v1 (multiple instances is MAY and deferred);
  - plugin API v1;
  - 1 MB plugin storage;
  - 10 actions per minute;
  - network proxy rate/size limits.
- The host watchdog hides/reloads a stuck webview; it does not restart the slideshow.

## 12. Security properties

- Plugin code runs only inside a sandboxed webview/iframe.
- No native APIs, filesystem, shell, or app storage access.
- No credentials, server URL, or library access.
- Network denied by default; host proxy for granted access.
- Plugin storage isolated and removed on uninstall.
- Plugin content cannot inject code into the host or another plugin.
- External links require confirmation and open outside the plugin.
- ZIP validation prevents traversal, bombs, and oversized content.
- Plugin failures are contained and logged.
- Installed bundles/assets work offline.

See [`security.md`](security.md) for the full threat model.

## 13. API versioning

- `apiVersion` is an integer; the host advertises a supported range.
- Breaking bridge/snapshot changes increment the API version and require a compatibility note.
- The app rejects plugins whose API version is unsupported.
- Manifest schema changes are versioned.
- Reference plugins are updated with the API.

## 14. Reference plugins

Bundled with the app:

- clock/time — enabled by default;
- weather — enabled by default, owns the location/unit/label settings;
- photo metadata — enabled by default;
- calendar/date — disabled by default;
- playback status — disabled by default;
- current image information — disabled by default.

They:

- use no network unless required;
- demonstrate time ticks, image-change updates, weather data, playback data, image metadata, and
  JSON settings;
- include icons, descriptions, and screenshots;
- replace the compiled clock/weather/metadata overlays. Migration maps the old `OverlaySettings`
  enabled state and weather coordinates/unit/label into the bundled plugin configuration.

No compiled-in clock, weather, or metadata overlay remains in v1. On devices below the WebView
baseline, the slideshow runs without overlays.

## 15. V1 exclusions

- Plugin marketplace/store, ratings, monetization.
- URL/catalog install; local ZIP only.
- Plugin signatures/checksums beyond a recorded SHA-256 and explicit consent.
- Multiple instances of the same plugin.
- Plugins on album selection or settings screens.
- Plugin access to the Immich API, album list, or library.
- Native code plugins, background services, or arbitrary file access.
- App-provided calendar feeds.
- WYSIWYG plugin authoring.
- Remote asset allowlists (future).

## 16. Testing

- ZIP validation: traversal, bombs, invalid manifests, duplicate IDs, missing entry, oversized
  screenshots/icons, invalid declared inputs.
- Install/update/enable/disable/uninstall and storage cleanup.
- Per-plugin settings screen rendering/validation and the plugin list icon/state.
- Built-in overlay migration: enabled state and weather settings survive upgrade.
- Sandbox: no host access, no direct network, no cross-plugin storage.
- Network proxy: permission/revocation, timeouts, rate limits.
- Placement: drag, resize, grid snap/grid size, clamping, safe areas, persistence, z-order.
- Input: buttons, links, external browser confirmation, blocked schemes.
- State: input filtering, 1 Hz coalescing, immediate events, pause conditions, hidden plugins.
- Actions: declared/granted/rate-limit violations.
- Failure: timeout, repeated errors, isolation from slideshow.
- Performance: 1 Hz updates with video playing; no frame drops.
- Android: WebView baseline, transparency, z-order, keyboard.
- Desktop: CEF transparency/input, Linux performance.
