# Architecture

Status: Draft v0.1
Related: [`plugins.md`](plugins.md), [`media.md`](media.md), [`data-cache.md`](data-cache.md),
[`platforms.md`](platforms.md), [`ADR-0001-stack.md`](ADR-0001-stack.md)

## 1. Context

The application is a full-screen photo frame for an Immich library. It runs continuously on a
Windows or Linux desktop and on Android tablets. It must:

- communicate directly with Immich;
- display original photos, videos, Live Photos, and GIFs with audio;
- cache media for offline playback;
- render interactive HTML/CSS/JS plugin overlays above media;
- keep the screen awake and optionally start at boot;
- preserve its state across restarts.

The existing Android application (`com.dav3.immichframe`) is a behavior reference, not a code base.
The new application is greenfield Flutter with a new identity (`com.rincew1nd.photoframe`).

## 2. Constraints

| Constraint | Consequence |
|---|---|
| Windows + Linux x64 + Android 8+ | Flutter is the single UI codebase; desktop and Android share domain/UI |
| No iOS, macOS, or Pi in v1 | No WKWebView, App Store, or ARM64 work |
| Strict original media | libmpv plus libheif/LibRaw instead of HTML5-only playback |
| Interactive HTML plugins above video | A transparent webview layer per plugin instance |
| HDR accepted as SDR tone-mapped | No native HDR surface or HDR compositor work |
| New application ID | Fresh install; no migration or shared signing |
| Sideloaded Android APK | In-app APK update flow; no Play Store policy dependency |
| 24/7 operation | Watchdogs, bounded caches, no unbounded memory or handles |

## 3. Stack

| Layer | Choice | Notes |
|---|---|---|
| UI | Flutter stable (3.47+ at planning time), Material 3 | Single codebase |
| State | Riverpod | Notifiers and providers; testable domain |
| Navigation | go_router | Deep links for settings groups and setup |
| Localization | Flutter gen-l10n / ARB | English fallback |
| HTTP | Dio | Interceptors for `x-api-key`; error mapping |
| Serialization | freezed + json_serializable | Immich DTOs and domain models |
| Cache DB | Drift + SQLite | Media metadata, plugin registry, cache state |
| Video/audio | media_kit + libmpv/FFmpeg | Hardware decode where available; tone-mapping |
| Stills | Flutter codecs, libheif, LibRaw via dart:ffi | HEIC/AVIF and DNG/ProRAW |
| Plugins desktop | webview_cef (CEF, offscreen rendering into a Flutter texture) | Windows and Linux |
| Plugins Android | webview_flutter (system WebView) | Plugin support depends on WebView version |
| Plugin host | Loopback HTTP server + sandboxed iframe + JS bridge | Shared across platforms |
| Secure storage | flutter_secure_storage | API key and OAuth tokens |
| Power/startup | Native channels, wakelock_plus, window_manager | Platform-specific |
| Biometrics | local_auth | Android; Windows Hello where available; Linux fail-open |
| Logging | logging + file sink + crash handler | Rotation and redaction |
| Updates | GitHub API + Android APK install; desktop release flow | Sideload-compatible |
| Tests | flutter_test; integration_test in later phases | Unit and widget now; integration and soak later |
| Build | GitHub Actions | Windows, Linux x64, Android |

## 4. App identity

- Application ID and Dart namespace: `com.rincew1nd.photoframe`.
- Android FileProvider: `com.rincew1nd.photoframe.fileprovider`.
- Android OAuth redirect: a custom scheme derived from the application ID; the exact URI is
  finalized during Phase 1.
- Desktop OAuth: system browser + loopback redirect.
- Windows app user model ID and Linux desktop file / window class use the same application ID.
- New signing key. Release builds are signed by a dedicated keystore stored in CI secrets.
- No data is read from `com.dav3.immichframe`; no migration UI is required.

## 5. Runtime architecture

```
+---------------------------------------------------------------+
| Flutter UI                                                    |
|  setup | albums | slideshow | settings | media selection      |
+----------------------------+----------------------------------+
                             |
+----------------------------v----------------------------------+
| Riverpod notifiers and domain services                        |
|  slideshow engine | filters/profiles | plugin registry        |
+----------------------------+----------------------------------+
                             |
+----------------------------v----------------------------------+
| Repositories                                                  |
|  Immich API | cache/sync | settings | plugin store | weather  |
+-------------+----------------+----------------+---------------+
              |                |                |
        +-----v-----+    +-----v------+   +-----v-----------------+
        | Immich    |    | Drift +    |   | Plugin host           |
        | HTTP      |    | file cache |   |  local server         |
        +-----------+    +------------+   |  CEF / Android WebView|
                                           |  sandbox + bridge     |
                                           +-----------------------+
```

### Slide show composition

The slideshow is a Flutter `Stack` with three logical layers:

1. Photo/video layer: image widget or media_kit video texture.
2. Plugin layer: one transparent interactive webview per plugin instance, positioned by the host.
   This includes the clock, weather, and metadata overlays, which ship as bundled example plugins.
3. App controls/dialogs layer: Flutter widgets.

### Plugin composition

Each plugin instance owns a rectangular box. The host positions the webview, clamps it to safe
areas, and persists placement. The user moves and resizes the box directly over the slideshow in an
edit mode or from the plugin's settings screen, optionally snapping to a configurable grid; the
plugin can also request a new placement through the host API. Clicks outside the box reach Flutter. On Android, if platform-view z-order prevents Flutter
controls from rendering above plugin webviews, the host temporarily hides plugin webviews while
controls or dialogs are open.

## 6. Layers and responsibilities

### Presentation

- Screens, navigation, theme, accessibility, localization.
- No direct Immich or filesystem access.
- Reads state from Riverpod providers and calls domain actions.

### Domain

- Slideshow sequencing, shuffle, filters, aspect classification, per-aspect profiles.
- Night-mode schedule, playback state, plugin state snapshot construction.
- Pure Dart where possible; unit-tested without Flutter or platform services.
- Defines interfaces for repositories and platform services.

### Data

- Immich client: authentication, permissions, albums, assets, thumbnails, originals, live-photo
  video, tags, EXIF.
- Cache: download, verification, metadata, prefetch, eviction, offline resolution.
- Settings: typed repository with migrations.
- Plugins: ZIP validation, installation, registry, configuration, storage.
- Weather: external provider for plugins that declare the weather input.

### Platform

- Keep-awake, display brightness/night mode, start-on-boot, launcher/home role, biometrics,
  single-instance behaviour, APK installation, secure storage, file paths.
- Exposed through interfaces with platform implementations.

### Plugin host

- Loopback server for host page and plugin assets.
- CEF/WebView lifecycle and transport.
- Sandbox policy, CSP, request interception.
- Bridge protocol, state fan-out, rate limits, failure isolation.
- Placement, visibility, z-order, safe areas.

## 7. Repository layout

```
lib/
  app/                    bootstrap, routing, theme, l10n setup
  core/                   shared models, clock, logging, errors
  features/
    setup/                server URL, auth, permission checks
    albums/               album selection
    slideshow/            slideshow screen, controls, overlays
    settings/             grouped settings, plugin management
    media_selection/      manual asset selection
  data/
    immich/               API client, DTOs, auth, permission checks
    cache/                Drift database, downloads, sync, eviction
    settings/             typed settings repository and migrations
    weather/              weather client
  domain/
    slideshow/            sequence, filters, profiles, state machine
    media/                player abstraction, live photos, image pipeline
  platform/               interfaces and platform implementations
Docs/                     this documentation
Plans/                    phase plans
test/
```

Phase 3/4/5 directories (native codecs, plugins, assets, scripts, and integration tests) will be added
when that work starts.

The project is a single Flutter application. Do not split into multiple packages until a concrete
need appears.

## 8. Data flow

### Immich connection

```
Setup UI -> AuthService -> Immich API -> permission probes -> secure storage
        -> SettingsRepository -> Album selection -> CacheSync
```

### Slideshow

```
Slideshow engine -> asset sequence -> cache resolver
                                   -> local file or network URL with headers
                                   -> media/image pipeline -> Flutter layer
                                   -> plugin snapshot -> plugin host
```

### Plugin state

```
Domain state changes
  -> snapshot builder (read-only, redacted)
  -> plugin host (coalesced, max 1 Hz)
  -> host page -> sandboxed plugin iframe
Plugin actions
  -> host page -> native bridge -> permission/rate-limit check
  -> slideshow action
```

## 9. Concurrency

- UI work stays on the Flutter UI isolate.
- Download, checksum, ZIP extraction/validation, and RAW/HEIC decode run in isolates or native
  worker threads.
- Decoded stills are written to a display-sized cache so the UI never decodes a full RAW image.
- media_kit owns its player threads. The app maps its event stream to domain state.
- Plugin webviews render on their own browser processes/threads. State delivery is asynchronous and
  coalesced; a slow plugin cannot block the slideshow.
- All long-running operations are cancellable and time-bounded.

## 10. Error handling

- Immich errors are mapped to typed failures (network, auth, permission, server, not found).
- Cache download failures retry with backoff; the slideshow continues with cached items or a
  no-items state.
- Malformed media falls back to an Immich preview or is skipped with a log entry.
- Plugin load/render failures hide that instance and increment a failure counter. Repeated failures
  disable the plugin and log the reason.
- A global crash handler writes a local report without secrets. Logs rotate and redact API keys,
  OAuth tokens, and Authorization headers.
- Watchdogs restart media/plugin hosts if they stop responding without restarting the app.

## 11. Key decisions

1. **Flutter, not a web shell.** Original codec support and transparent plugin compositing dominate
   the decision. See `ADR-0001-stack.md`.
2. **Native media via libmpv.** HTML5 video cannot guarantee original codecs on all targets.
3. **Tone-mapped SDR.** True HDR would require a per-platform native video surface and break the
   single Flutter compositor.
4. **Per-instance transparent plugin webviews.** Enables click-through, input, movement, and failure
   isolation. A single full-screen overlay would swallow input.
5. **Host-mediated plugin capabilities.** Network, storage, actions, and placement are explicit host
   APIs, not direct access.
6. **Local ZIP plugin distribution.** No marketplace, remote install, or signatures in v1.
7. **All overlays are plugins.** Clock, weather, and metadata ship as bundled HTML/CSS/JS plugins;
   the compiled overlay widgets have been removed.
8. **No data migration from the legacy app.** New application ID; fresh setup.
9. **No Pi/iOS/macOS.** The architecture stays portable but no platform work is done.

## 12. Build and packaging

| Platform | Artifact | Notes |
|---|---|---|
| Android | APK per ABI (arm64-v8a, armeabi-v7a) | Sideload; in-app update; new keystore |
| Windows | Installer or ZIP | CEF + libheif/LibRaw + libmpv bundled or linked |
| Linux x64 | AppImage and/or .deb | X11 primary; bundle native libraries |

CEF is downloaded at build time and bundled. libheif and LibRaw are built from pinned sources for
each target. media_kit provides libmpv on Windows/Android; Linux uses a pinned system/bundled libmpv
with FFmpeg codecs.

## 13. Risks

| Risk | Mitigation |
|---|---|
| CEF transparent OSR/input issues | Phase 0 spike; patch webview_cef; fallback to a different overlay design |
| Android platform-view z-order | Spike; hide plugin webviews while controls/dialogs are open |
| Linux software OSR cost | Small per-plugin webviews; low OSR frame rate; 1 Hz state pushes |
| libmpv codec availability | Pin FFmpeg build; test HEVC/AV1/ProRes; fallback to Immich playback stream |
| DNG/ProRAW quality/performance | LibRaw version test; embedded preview first; screen-sized cache |
| WebView version on no-GMS devices | Runtime version check; disable plugins below baseline; slideshow runs without overlays |
| All overlays depend on the plugin host | Ship clock/weather/metadata as bundled example plugins; compiled overlays are removed |
| 24/7 leaks | Soak tests, bounded caches, watchdog restarts |
| Plugin supply chain | Explicit ZIP import, permission consent, sandbox, no secrets exposed |
| HEVC patent licensing | Legal review before broad commercial distribution |

## 14. Related documents

- Media: [`media.md`](media.md)
- Plugins: [`plugins.md`](plugins.md)
- Data and cache: [`data-cache.md`](data-cache.md)
- Platforms: [`platforms.md`](platforms.md)
- Security: [`security.md`](security.md)
- Licensing: [`licensing.md`](licensing.md)
- Tests and CI: [`testing-ci.md`](testing-ci.md)
- Requirements alignment: [`requirements-alignment.md`](requirements-alignment.md)
