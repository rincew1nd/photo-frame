# Photo Frame Requirements

Status: Draft v0.4 (Phase 4 overlay/plugin decisions applied)
Applies to: Photo Frame cross-platform photo frame (`com.rincew1nd.photoframe`)
Related docs: [`Docs/README.md`](Docs/README.md), [`Docs/requirements-alignment.md`](Docs/requirements-alignment.md)

This document defines product requirements. It is the source of truth for what the
app must do; implementation detail belongs in the technical documentation. Existing
behaviour is preserved unless a requirement below explicitly changes it.

The original Android-only application (`com.dav3.immichframe`) remains a separate
product. This document now applies to the greenfield cross-platform application.

Priority keywords:

- **MUST** - required for the release.
- **SHOULD** - expected, but may be deferred with a documented reason.
- **MAY** - optional / future.

### 1.1 Platform applicability

| Platform | V1 status |
|---|---|
| Windows 10/11 x64 | Supported |
| Linux x64 (Ubuntu/Debian) | Supported; X11 primary; Wayland unvalidated (no Linux host) |
| Android 8.0+ (API 26) | Supported |
| iOS, macOS | Out of scope |
| Raspberry Pi / Linux ARM64 | Out of scope |
| True HDR output | Out of scope; HDR/10-bit is tone-mapped to SDR |

Android-only requirements have desktop equivalents where applicable:

| Requirement | Android | Windows/Linux desktop |
|---|---|---|
| BR-07 biometric gate | BiometricPrompt/device credential | Windows Hello where available; Linux fails open |
| BR-09 night mode | Window brightness and overlay | Overlay dimming; no universal panel-brightness API |
| BR-10 start on boot | Boot receiver | Windows startup entry; Linux XDG autostart/systemd user service |
| BR-10 launcher role | HOME intent filter | Kiosk/fullscreen mode; no launcher replacement |
| BR-12 keep screen on | `FLAG_KEEP_SCREEN_ON`/wakelock | `SetThreadExecutionState`; logind/DBus inhibit |
| BR-12 cutouts/insets | Window insets/safe areas | Safe area reported by the OS, usually zero |

---

## 1. Baseline Product Requirements

These capabilities already exist and must not regress.

| ID | Requirement | Priority |
|---|---|---|
| BR-01 | Connect to an Immich server by URL using an API key generated in-app, entered manually, or obtained via OAuth (PKCE). | MUST |
| BR-02 | Verify the five required API permissions after connecting; block setup only on missing blocking permissions and degrade optional features when `asset.download` is missing. | MUST |
| BR-03 | List and select one or more albums; persist the selection across restarts. | MUST |
| BR-04 | Play a full-screen slideshow of photos, Live Photos, videos, and animated GIFs with configurable interval, shuffle, and transition. | MUST |
| BR-05 | Cache media for offline playback, prefetch the next slide, and continue the slideshow when the server is unreachable. | MUST |
| BR-06 | Provide in-slideshow controls: previous, next, pause/resume, mute/unmute, album selection, media selection, and settings. | MUST |
| BR-07 | Protect media/library navigation and API-key reveal/copy with biometric or device-credential authentication where a screen lock exists; fail open for navigation on devices without a lock. | MUST |
| BR-08 | Provide clock, current weather, and photo metadata overlays as bundled example plugins, each independently enabled, configurable, and removable. | MUST |
| BR-09 | Support night mode: dim to a configured brightness during a scheduled window, including overnight windows. | MUST |
| BR-10 | Support start-on-boot, launcher mode (home replacement), and in-app update checks from GitHub releases. | MUST |
| BR-11 | Persist all user settings across restarts and apply changes without reinstalling. | MUST |
| BR-12 | Run continuously as a photo frame: keep the screen on when configured, avoid OLED burn-in through photo motion, and respect display cutouts/system insets. | MUST |
| BR-13 | Localize all app-owned UI strings in the supported locales. | MUST |
| BR-14 | Never log or expose the API key, server credentials, or other secrets. | MUST |

---

## 2. Media Filters and Per-Aspect Settings

### 2.1 Type filter

| ID | Requirement | Priority |
|---|---|---|
| MR-01 | The user can independently show or hide **Photos**, **Live Photos**, and **Videos**. The filter is multi-select and persists across restarts. | MUST |
| MR-02 | At least one media type must remain selected. Disabling the last selected type must be prevented. | MUST |
| MR-03 | A Live Photo is classified as **Live Photo**, not Photos. Animated GIFs are classified as **Photos**. | MUST |
| MR-04 | All three types are enabled by default on a fresh install. No migration from the legacy app is performed; the legacy "Skip Videos" value is not read. | MUST |
| MR-05 | When `asset.download` is denied, **Videos** is locked off with an explanatory hint. Live Photos remain available. | MUST |
| MR-06 | The existing standalone "Skip Videos" toggle is replaced by the type filter. | MUST |

### 2.2 Aspect-ratio filter

| ID | Requirement | Priority |
|---|---|---|
| AR-01 | The user can independently show or hide these aspect buckets: **1:1**, **4:3**, **3:2**, **16:9**, **Panorama**. The filter is multi-select and persists. | MUST |
| AR-02 | Buckets are orientation-neutral: 3:4 is treated as 4:3, 2:3 as 3:2, 9:16 as 16:9, and tall panoramas as Panorama. | MUST |
| AR-03 | Classification uses the longer side divided by the shorter side: below 1.15 = 1:1; below 1.42 = 4:3; below 1.64 = 3:2; below 2.0 = 16:9; otherwise Panorama. 5:4 maps to 4:3. | MUST |
| AR-04 | At least one aspect bucket must remain selected. | MUST |
| AR-05 | All aspect buckets are enabled by default. | MUST |
| AR-06 | Assets whose dimensions are missing or invalid are **always shown** and are not affected by the aspect filter. They use the Default profile. | MUST |
| AR-07 | Aspect metadata comes from Immich EXIF image width/height and is persisted for offline playback. No new server endpoint is required. | MUST |

### 2.3 Per-aspect settings profiles

| ID | Requirement | Priority |
|---|---|---|
| AP-01 | Image fit (**Contain** / **Cover**), Live Photo mode (**Off** / **Live** / **Loop**), and Pan strength (0-100) are configurable per aspect bucket. | MUST |
| AP-02 | A **Default** profile exists and applies to assets with unknown aspect and to any bucket without an override. Its values are the existing global image-fit, Live-Photo-mode, and pan-strength settings. | MUST |
| AP-03 | Editing a bucket for the first time seeds that bucket from the Default profile. Later Default changes do not overwrite an existing bucket override. | MUST |
| AP-04 | The effective profile is resolved per displayed asset. Image fit applies to photos, Live Photos, and videos. Live Photo mode applies only to Live Photos. Pan strength applies only to photo imagery. | MUST |
| AP-05 | Pan strength greater than zero forces Cover, because panning requires image overflow. Pan strength zero disables animation for that asset and honours the profile's Image fit (so a Panorama bucket can stay Contain). | MUST |
| AP-06 | Per-aspect profiles persist across restarts. | MUST |
| AP-07 | The filter and profile settings control UI presents the Default profile and the five buckets without duplicating the same controls in other Settings sections. | MUST |

### 2.4 Filter interaction and feedback

| ID | Requirement | Priority |
|---|---|---|
| MF-01 | Manual media selection, type filtering, and aspect filtering combine with AND semantics. | MUST |
| MF-02 | If filters remove every asset, the slideshow shows a clear "no items match the current filters" state instead of an empty or black frame. | MUST |
| MF-03 | The media-selection counter reflects the number of assets that would actually play after filters. The grid still lists all assets so manual selection remains possible. | SHOULD |
| MF-04 | Changing filters or profiles applies when the slideshow is next shown or reloaded; changes must not require an app restart. | MUST |

### 2.5 HDR and format support

| ID | Requirement | Priority |
|---|---|---|
| MED-01 | HDR/10-bit originals are decoded and tone-mapped to SDR. True HDR output, HDR10+ dynamic metadata, and Dolby Vision are out of scope. The app must not claim HDR or Dolby Vision output. | MUST |
| MED-02 | Video/audio uses libmpv/FFmpeg via media_kit. Stills use Flutter codecs for JPEG/PNG/WebP/BMP/GIF, libheif for HEIC/HEIF/AVIF, and LibRaw for DNG/ProRAW. | MUST |
| MED-03 | HEVC, AV1, VP9, MPEG-4/MPEG-2, ProRes, and DNxHD are supported where the bundled FFmpeg/libmpv build provides them. Software decode is allowed; performance is not guaranteed on all hardware. | MUST |
| MED-04 | Unsupported or corrupt originals fall back to the Immich preview/playback stream or are skipped with a logged diagnostic; the app must not crash. | MUST |
| MED-05 | Still-image decode happens off the UI thread and is downscaled to display size plus pan headroom; full RAW images are never decoded on the UI thread. | MUST |
| MED-06 | Local cache is used before network media. If the network is unavailable and nothing is cached, the slideshow shows the no-items state. | MUST |
| MED-07 | “Play originals” is bounded by the bundled decoder matrix, not an unbounded promise for every camera format. Other RAW formats (CR2/CR3/NEF/ARW) are not required. | MUST |
| MED-08 | Live Photos play their motion video with audio according to the effective profile, falling back to the still when motion is unavailable. | MUST |

---

## 3. Modular Plugin System

### 3.0 Implementation status (2026-11-01)

Phase 4 is implemented: manifest/ZIP validation, DB v4, the plugin store/seeder, loopback host,
webview adapters, snapshot/bridge/session, plugin management UI, slideshow placement with
drag/resize/grid, and bundled example plugins. Every overlay — including clock, weather, and
metadata — is a plugin rendered by the host, with its own settings screen and draggable/resizable
placement. The compiled Flutter overlays and their legacy `OverlaySettings` configuration have been
removed; plugins are the only overlay system.

The cached `tags` field is always empty because sync never populates it; tag support requires a sync
change or an explicit requirement amendment. Weather for plugins is fetched through
`SlideshowController.refreshWeatherAt()` using the weather plugin's own settings.

### 3.1 Model and package format

| ID | Requirement | Priority |
|---|---|---|
| PLG-01 | The app supports installable plugins that render HTML/CSS overlays and read application data. | MUST |
| PLG-02 | A plugin is a self-contained bundle containing a JSON manifest, an HTML document, a CSS stylesheet, optional sandboxed script, optional local assets, optional screenshots, and an optional icon. | MUST |
| PLG-03 | The manifest declares at minimum: plugin ID, name, version, author, homepage/site, description, app/API compatibility, requested permissions, requested snapshot inputs, JSON settings schema, update triggers, optional actions, optional icon, and default placement. | MUST |
| PLG-04 | The manifest, settings schema, inputs, icon, and screenshots are validated on install. Invalid, incompatible, or duplicate-ID plugins are rejected with a readable error. | MUST |
| PLG-05 | Plugins from a local ZIP are installed explicitly by the user. Installing a plugin must show its identity, version, icon, requested permissions, and requested inputs before activation. Bundled example plugins are the only exception: they are seeded on first run without a ZIP picker. | MUST |

### 3.2 Lifecycle management

| ID | Requirement | Priority |
|---|---|---|
| PLG-06 | The user can install, enable, disable, update, uninstall, and inspect installed plugins. Each installed plugin has a dedicated settings screen reachable from the plugin list; its configuration, placement, permissions, and lifecycle controls live there. | MUST |
| PLG-07 | Disabling or uninstalling a plugin removes its overlay immediately and frees its resources. | MUST |
| PLG-08 | Uninstalling a plugin removes its plugin-scoped storage and configuration. | MUST |
| PLG-09 | Updates preserve user configuration when the settings schema remains compatible; incompatible updates require confirmation. | SHOULD |
| PLG-10 | Multiple instances of the same plugin MAY be allowed, each with its own configuration and placement. | MAY |

### 3.3 Placement and rendering

| ID | Requirement | Priority |
|---|---|---|
| PLG-11 | Plugins render in an overlay layer above the current photo/video but below app controls and dialogs. | MUST |
| PLG-12 | Each plugin instance has a persisted position, size, and z-order. Placement uses free normalized coordinates with direct drag-and-drop movement and edge/corner resizing over the slideshow (edit mode) and from the plugin's settings screen; 3x3 anchors remain available as defaults. The Plugins screen provides an optional snap-to-grid toggle and a configurable grid size, both persisted. | MUST |
| PLG-13 | Placement respects safe areas for display cutouts and system bars. | MUST |
| PLG-14 | Each instance can be shown or hidden independently without uninstalling it. | MUST |
| PLG-15 | Plugins are hidden during night mode by default; a per-instance "show during night mode" option MAY exist. | SHOULD |
| PLG-16 | Plugins are hidden when the slideshow is not visible or the screen is off, and stop receiving updates while hidden. | MUST |
| PLG-17 | A plugin failure must never cover or block the slideshow. Failed plugins are removed from the overlay and reported in the app log. | MUST |

### 3.4 Exposed application data

Plugins receive a read-only state snapshot. They cannot read arbitrary app storage,
the photo library, the API key, the server URL, or credentials.

| ID | Requirement | Priority |
|---|---|---|
| PLG-18 | **App data**: app version, plugin API version, locale, time zone, theme, viewport size, safe-area insets, night-mode state. | MUST |
| PLG-19 | **Time data**: current epoch time, local time, date, time zone, and locale. | MUST |
| PLG-20 | **Weather data**: current temperature, unit, weather code/description, and location label when a plugin declares the weather input and weather is available; otherwise null. Weather is fetched by the host from the bundled weather plugin's location/unit settings. | MUST |
| PLG-21 | **Playback data**: playing/paused state, current index, total count, interval, elapsed progress, muted state, and slideshow-running state. | MUST |
| PLG-22 | **Image data**: current asset ID, media type, Live Photo flag, dimensions, aspect bucket, MIME type, cached/offline state, EXIF date, description, location, and tags. | MUST |
| PLG-23 | **Calendar data**: current date/time is always available; calendar events are optional. A calendar plugin may fetch an external ICS/CalDAV feed only with the Network permission. App-provided event feeds are out of scope for v1. | SHOULD |
| PLG-24 | Plugins never receive credentials, server URL, API key, full album lists, or unrelated library metadata. | MUST |

### 3.5 Update and event model

| ID | Requirement | Priority |
|---|---|---|
| PLG-25 | The app pushes a fresh state snapshot (declared inputs plus mandatory app/time) and a **time tick** at most once per second while the slideshow is visible. | MUST |
| PLG-26 | The app pushes an immediate update on any declared input change, including image change, playback state change, weather refresh, settings change, viewport/orientation change, and plugin enable/install. | MUST |
| PLG-27 | Plugins do not need to poll; update delivery is event-driven. A plugin may request a refresh, subject to the once-per-second limit. | MUST |
| PLG-28 | Time ticks pause while the screen is off, the app is backgrounded, or the plugin is hidden. | MUST |
| PLG-29 | Update delivery is throttled and dropped updates are coalesced so a slow plugin cannot stall the slideshow. | MUST |

### 3.6 Plugin behaviour and actions

| ID | Requirement | Priority |
|---|---|---|
| PLG-30 | Plugins may change their own rendering and behaviour based on the exposed snapshot and events. | MUST |
| PLG-31 | A plugin may invoke app actions only when those actions are declared in its manifest and granted by the user. Supported actions: next, previous, pause/resume, mute/unmute, open settings, open media selection. | SHOULD |
| PLG-32 | Plugin actions are rate-limited and cannot modify server, credentials, permissions, or other plugin configuration. | MUST |
| PLG-33 | Plugin actions run only while the slideshow is visible and the plugin is enabled. | MUST |

### 3.7 JSON settings

| ID | Requirement | Priority |
|---|---|---|
| PLG-34 | A plugin declares its configuration fields in the manifest as a JSON settings schema. | MUST |
| PLG-35 | Supported field types: text, multiline text, number, boolean, select, color (including alpha), and URL. Number fields can express opacity. Each field declares a label, default, optional help text, and validation constraints where applicable. | MUST |
| PLG-36 | The app renders the settings UI from the schema on the plugin's dedicated settings screen and validates values before applying them. | MUST |
| PLG-37 | Configuration is stored per plugin instance and passed to the plugin as read-only data. | MUST |
| PLG-38 | Changing a plugin setting triggers an immediate plugin update without restarting the slideshow. | MUST |
| PLG-39 | Plugin UI labels may be supplied by the plugin; app-owned labels and settings chrome must be localized. | MUST |

### 3.8 Bundled example plugins

| ID | Requirement | Priority |
|---|---|---|
| PLG-40 | Ship bundled example plugins for clock/time, calendar/date, weather, playback status, and current image information. | SHOULD |
| PLG-41 | Bundled examples are seeded on first run and use the same ZIP validation, manifest, registry, settings, and host path as a plugin from any other developer. Clock/weather/metadata start enabled; other examples start disabled. After seeding they have no special status: the user can disable or uninstall/delete any of them, and deletion is not undone automatically. None request network permission unless needed. | MUST |
| PLG-42 | Bundled examples demonstrate time ticks, image-change updates, weather data, playback data, image metadata, icons, screenshots, and JSON settings. | SHOULD |
| PLG-43 | Clock, weather, and photo-metadata overlays are bundled example plugins, not compiled-in Flutter widgets. Fresh installs enable them by default. Once seeded, they are ordinary removable plugins, and no compiled-in overlay remains in v1. | MUST |

### 3.9 Security, privacy, and reliability

| ID | Requirement | Priority |
|---|---|---|
| PLG-44 | Plugin HTML/CSS/script runs in an isolated sandbox with no access to app files, credentials, or native APIs. | MUST |
| PLG-45 | Network access is denied by default and granted per plugin only with explicit user consent. Domain restrictions MAY be configurable. | MUST |
| PLG-46 | Plugin-scoped storage is isolated and removed on uninstall. | MUST |
| PLG-47 | Plugin content cannot inject executable code into the host app or escape into another plugin's storage. | MUST |
| PLG-48 | Plugin errors, timeouts, and hangs are contained; repeated failures disable the plugin and log the reason. | MUST |
| PLG-49 | Installed plugins and their local assets work offline. Remote assets are the plugin's responsibility and must fail gracefully. | MUST |
| PLG-50 | The total time to render plugin overlays must not delay the next slide or make the slideshow janky. | MUST |
| PLG-51 | The app exposes a versioned plugin API and documents breaking changes. | MUST |

### 3.10 Plugin bundle, security, and API decisions

| ID | Requirement | Priority |
|---|---|---|
| PLG-52 | Plugins are installed from local ZIP files only (no URL/catalog install). A bundle contains `plugin.json` plus HTML/CSS/optional JS/assets/screenshots/icon; the ZIP may have one top-level folder. Limits: 20 MB compressed, 100 MB extracted, 500 files. Reject traversal, symlinks, zip bombs, native binaries, remote code includes, missing entry, and duplicate IDs. | MUST |
| PLG-53 | The manifest declares id, name, version, apiVersion, author, homepage/site, license, description, entry, optional icon, optional screenshots, permissions, inputs, actions, update triggers, placement, and settings schema. Icons and screenshots are shown as untrusted images in the list/install/details UI. | MUST |
| PLG-54 | Plugin overlays are interactive (buttons, links, form controls, text input where available), can request placement changes, support drag/resize with optional grid snap, and are clamped to safe areas. Placement, size, grid settings, and z-order persist; app controls/dialogs remain above. | MUST |
| PLG-55 | Plugins run in a sandboxed iframe with an opaque origin (`allow-scripts`, no `allow-same-origin`) inside a per-instance transparent webview. They cannot read host storage, cookies, files, secure storage, the API key, server URL, album list, or other plugins. | MUST |
| PLG-56 | Network is denied by default; granted requests are host-proxied with timeouts, response-size limits, rate limits, and no Immich credentials. Domain allowlists are not implemented in v1; this residual risk is documented. | MUST |
| PLG-57 | External links are intercepted and opened in the system browser after confirmation. `file:`, `javascript:`, `intent:`, `data:` navigation, popups, and in-app navigation are blocked. | MUST |
| PLG-58 | The host bridge and snapshot are versioned (v1). Plugin storage is namespaced per instance, size-limited, and removed on uninstall. Actions are declared, user-granted, and rate-limited (default 10/minute). | MUST |
| PLG-59 | A failed, hung, or repeatedly erroring plugin is hidden/disabled and logged; it must not block the slideshow. Load timeout defaults to 10 seconds; repeated failures within five minutes disable the plugin. | MUST |
| PLG-60 | On Android devices below the WebView baseline (Chromium 100+), plugins are disabled with an explanatory message. Because all overlays are plugins, the slideshow continues without overlays on those devices. Desktop plugin rendering targets CEF 149; Phase 0 found that `webview_cef` 0.6.2 exposes no transparency/background API, so CEF/OSR transparency must be patched or replaced and verified before Phase 4 host work. | MUST |
| PLG-61 | The manifest declares the snapshot sections a plugin needs (`inputs`); the host delivers only those sections plus mandatory app/time data. The install/details UI discloses the requested inputs. | MUST |

---

## 4. Compact Settings Menu

| ID | Requirement | Priority |
|---|---|---|
| SET-01 | Settings are organized into collapsible groups rather than one long scrolling page. | MUST |
| SET-02 | Groups: **Playback**, **Media Filters & Aspect**, **Display**, **Plugins**, **Automation**, **Media Cache**, **Connection & Security**, **About & Diagnostics**. | MUST |
| SET-03 | Each group header shows a title and a one-line summary of its current state. | MUST |
| SET-04 | Groups can be expanded/collapsed independently. The expanded state persists for the session or device. | MUST |
| SET-05 | The first group starts expanded; all others start collapsed unless a deep link or onboarding tour targets them. | SHOULD |
| SET-06 | Moving controls between groups must preserve onboarding tour targets and back-navigation behaviour. | MUST |
| SET-07 | Media type and aspect filters, per-aspect profiles, Default profile, and plugin management live in their designated groups, not duplicated elsewhere. | MUST |
| SET-08 | A settings search field that filters and jumps to matching settings is desirable. | MAY |
| SET-09 | The settings screen must remain usable on small screens with large font scaling and must not introduce nested scrolling. | MUST |

---

## 5. Non-Functional Requirements

| ID | Requirement | Priority |
|---|---|---|
| NFR-01 | The slideshow starts without waiting for plugin or overlay initialization. | MUST |
| NFR-02 | Plugin updates at 1 Hz must not cause visible slideshow frame drops on supported devices. Use coalesced state, per-instance small webviews, and low-rate OSR. | MUST |
| NFR-03 | The app must run for days without leaking memory, file handles, or player instances; soak targets are 24 hours for Phase 2 and 72 hours for the release gate. | MUST |
| NFR-04 | Network loss, server downtime, album deletion, and malformed media must degrade gracefully without crashing. | MUST |
| NFR-05 | All new settings and plugin state survive app restart and normal process death. | MUST |
| NFR-06 | New UI strings are added to all supported locales; missing translations fall back to English. | MUST |
| NFR-07 | The app must remain compatible with Android 8.0 (API 26) and above. Plugin rendering requires system WebView/Chromium 100+ on Android; below that baseline plugins (and therefore all overlays) are disabled with an explanation while the slideshow continues. Desktop plugin rendering targets CEF 149, but Phase 0 found `webview_cef` 0.6.2 lacks a transparency API; the gate must be resolved before plugins ship. | MUST |
| NFR-08 | Plugin permissions, network access, and data exposure are disclosed in the settings UI. | MUST |
| NFR-09 | No plugin may access the Immich API directly; all app data comes through the versioned snapshot. | MUST |
| NFR-10 | Documentation is updated in the same change as any requirement-affecting code. | MUST |

---

## 6. Acceptance Scenarios

1. **Type filter**: Disable Videos. Videos no longer appear after returning to the slideshow; photos and Live Photos remain. Re-enable Videos; they return without an app restart.
2. **Type filter protection**: Attempt to disable the last remaining media type. The UI keeps it enabled.
3. **Aspect filter**: Enable only 16:9 and Panorama. A 4:3 photo is skipped; a 16:9 photo and a 3:1 panorama play. A photo with missing dimensions still plays.
4. **Per-aspect fit**: Set 16:9 to Cover, 4:3 to Contain, Panorama to Contain with pan strength 0. Each bucket renders accordingly; portraits use the 4:3 profile.
5. **Animation rule**: Set a bucket to Contain with pan strength greater than 0. The asset fills the screen while animating; setting pan strength to 0 restores Contain.
6. **Unknown metadata**: A video without width/height is never hidden by the aspect filter and uses the Default profile.
7. **Empty filters**: A filter combination that matches nothing shows the no-match message rather than a black frame.
8. **Plugin install**: Install a valid plugin. It appears in the plugin list with its icon, its permissions and requested inputs are shown, and opening it exposes its own settings screen and placement editor.
9. **Plugin update cadence**: A clock plugin updates every second; an image-info plugin updates immediately when the image changes; a played/paused plugin updates on state change.
10. **Plugin failure**: A plugin that throws or hangs is removed/disabled without interrupting the slideshow.
11. **Plugin security**: A plugin without Network permission cannot make outbound requests; no plugin can read the API key or server URL.
12. **Settings groups**: All groups collapse and expand; the tour can open the group containing its target; the settings screen does not duplicate media filter or profile controls.
13. **Persistence**: Filters, profiles, plugin configuration, and placement survive app restart.
14. **Permission degradation**: With `asset.download` denied, Videos is locked off and the slideshow continues with photos and Live Photos.
15. **All overlays as plugins**: Clock, weather, and metadata are bundled example plugins and the only overlay system; compiled overlays have been removed. Fresh installs enable them by default. Disable and delete each through the normal plugin controls; they do not return automatically.
16. **Per-plugin settings**: Open Plugins → Clock → settings, change the time format, and see the clock overlay update immediately without restarting the slideshow.
17. **Placement editor**: Drag a plugin, resize it, enable grid snap, change the grid size, and confirm the placement and grid settings survive restart; the box stays inside the safe area.

---

## 7. Out of Scope (v1)

- A public plugin store, marketplace, ratings, or monetization.
- Plugin access to the Immich API, album list, or the full photo library.
- Plugins running background services or modifying the app outside granted actions.
- Server-side calendar integration; calendar events are plugin-fetched ICS/CalDAV only.
- iOS, macOS, Raspberry Pi, Linux ARM64, or non-Android mobile clients.
- True HDR output; HDR10+ dynamic metadata and Dolby Vision.
- WYSIWYG plugin authoring inside the app.
- Arbitrary native code plugins.

---

## 8. Resolved Decisions

The Phase 0 product decisions formerly tracked as open questions:

| Question | Decision |
|---|---|
| Plugin scripts | Sandboxed HTML/CSS/JavaScript; not Dart, because runtime-installed Dart cannot be safely sandboxed and would expose the host process |
| Plugin distribution | Local ZIP only; no URL install or catalog in v1. Bundled example plugins are seeded on first run and are ordinary removable plugins afterward. |
| Plugin bundle contents | `plugin.json` metadata/settings/inputs, HTML/CSS/optional JS, optional screenshots and icon |
| Signatures | No signatures in v1; explicit consent, permissions shown, SHA-256 recorded |
| Plugin screens | Plugin rendering is slideshow-only in v1; per-plugin settings screens are app-rendered |
| Plugin limits | 20 MB ZIP, 100 MB extracted, 500 files, 20 installed, 10 active, one instance per plugin in v1, 1 MB storage, 10 actions/minute, API v1 |
| Built-in overlays vs plugins | All overlays are bundled example plugins, including clock/weather/metadata; they can be disabled or deleted like any plugin, and compiled-in overlays are removed |
| Plugin placement | Free drag-and-drop with resize; optional snap-to-grid with a persisted grid size in the Plugins screen |
| Plugin settings | Each installed plugin has its own settings screen rendered from its manifest schema |
| Plugin playback actions | Declared and user-granted next/previous/pause/mute/open settings/open media selection; rate-limited |
| Network allowlist | No domain allowlist in v1; host-proxied network with explicit permission and documented residual risk |

Remaining product decisions (not blocking implementation): final display name/branding, final locale list, desktop installer
formats, app icon, Windows Hello/Linux biometric behaviour, desktop update UX, and post-v1 multiple instances per plugin.

---

## 9. Licensing and Legal

- The application license is MIT.
- Third-party notices and LGPL dynamic-linking compliance are required for bundled native libraries (libmpv/FFmpeg, CEF, libheif, LibRaw).
- Do not ship GPL-only codec features.
- HEVC patent licensing is a separate legal question and must be documented before commercial distribution.
- Do not claim Dolby Vision or true HDR support.

---

## 10. Glossary

- **Asset**: A photo, video, Live Photo, or GIF stored in Immich.
- **Live Photo**: A still image with an associated short motion video.
- **Aspect bucket**: One of 1:1, 4:3, 3:2, 16:9, or Panorama, derived from orientation-neutral dimensions.
- **Default profile**: The fallback Image fit / Live Photo mode / Pan strength values.
- **Plugin**: An installable HTML/CSS/JSON bundle that renders an overlay from app data.
- **Snapshot**: The read-only application state object delivered to plugins.
- **Time tick**: The once-per-second update event while the slideshow is visible.
