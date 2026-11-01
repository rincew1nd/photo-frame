# ADR-0001: Cross-platform stack

- Status: Accepted
- Date: 2026-10-27

## Context

The application must run on Windows 10/11 x64, Linux x64, and Android 8+ (API 26), with a possible
future extension elsewhere. It is a greenfield application with its own identity.

The hard requirements are:

- direct Immich API communication;
- playback of original photos, videos, Live Photos, GIFs, and audio;
- a local offline cache;
- interactive HTML/CSS/JS plugin overlays above video and photos;
- sleep prevention and start-on-boot;
- continuous 24/7 operation;
- priority on original media over server transcodes.

The dominant technical tensions are:

1. **Original codecs.** HTML5 video in a webview cannot reliably decode arbitrary originals
   (HEVC, AV1, ProRes, HEIC, DNG/ProRAW) across Windows, Linux, and Android.
2. **Transparent plugin overlays.** Plugins need real HTML/CSS/JS, transparency, input, movement,
   and isolation while sitting above native video and below app controls.
3. **Codebase cost.** Maintaining a native desktop app and a separate Android app duplicates the
   entire UI and plugin host.
4. **Platform floor.** Modern cross-platform runtimes require API 24+; the product target is API 26.

## Decision

Use **Flutter** for a single application, with:

- `media_kit`/libmpv for video, audio, and Live Photo motion;
- libheif and LibRaw via FFI for HEIC/AVIF and DNG/ProRAW stills;
- `webview_cef` (CEF offscreen rendering into a Flutter texture) for desktop plugin overlays;
- `webview_flutter` (system WebView) for Android plugin overlays;
- a loopback HTTP server and sandboxed iframes for the plugin host;
- Flutter-rendered app UI and controls above plugin webviews.

HDR/10-bit originals are decoded and tone-mapped to SDR. True HDR output is out of scope.

## Alternatives considered

| Stack | Original codecs | Transparent HTML overlay | Reuse | Assessment |
|---|---|---|---|---|
| Flutter + media_kit + CEF/WebView | Excellent via libmpv/FFmpeg | Feasible with the patched `webview_cef` fork | None | **Chosen** |
| Kotlin Multiplatform + Compose | Android media good; desktop integration custom/young | Custom JCEF/CEF OSR | High if keeping the old app | Rejected for this greenfield app; higher desktop risk |
| Electron + Capacitor | Poor for originals; HTML5 codecs only | Trivial | None | Rejected: strict originals |
| Tauri 2 | Poor; system WebView codecs | Web UI easy; native video compositing unsolved | Rust core | Rejected: originals and mobile maturity |
| Qt/QML + libmpv + QtWebEngine (desktop) + native Android | Excellent | Excellent on desktop | None | Rejected: two codebases; not a single app |
| Avalonia + LibVLC + WebView | Good via LibVLC | WebView transparency/OSR immature | C# only | Rejected: plugin overlay risk and team fit |

## Consequences

### Positive

- One UI/domain codebase for all targets.
- libmpv gives broad original video/audio support, including hardware decode where available.
- CEF is the same Chromium generation on Windows and Linux; plugin behavior is consistent.
- Android uses the system WebView, avoiding a second bundled browser engine.
- Interactive plugins are possible with real HTML/CSS/JS, sandboxing, and input.
- All overlays, including clock/weather/metadata, can share one plugin host instead of maintaining
  separate compiled overlay code.

### Negative

- No reuse of the existing Kotlin/Compose application.
- True HDR output is not possible; HDR content is tone-mapped to SDR.
- All overlays depend on the WebView/CEF host; below the Android baseline the frame has no overlays.
- CEF adds a large desktop binary and a software readback path on Linux.
- Canvas/CEF transparency and Android platform-view z-order are the highest technical risks.
- Android plugin support depends on the system WebView version.
- Flutter and CEF require a substantial native build/release pipeline.

## Risks and mitigations

| Risk | Mitigation |
|---|---|
| CEF transparent OSR or input does not work | Patch `webview_cef` for transparent painting (done in the pinned fork); if unresolved, re-evaluate stack |
| Android controls cannot render above the WebView | Hide plugin webviews while controls/dialogs are open |
| Linux full-screen CEF readback is too expensive | Per-plugin small webviews; low OSR frame rate; only push state at 1 Hz |
| libmpv build lacks a needed codec | Pin FFmpeg/libmpv build; test HEVC/AV1/ProRes; Immich playback stream as last resort |
| ProRAW is not handled well by LibRaw | Test early; use embedded preview fallback; document limitations |
| Android WebView is old or missing | Version check; degrade plugins; slideshow runs without overlays because all overlays are plugins |
| 24/7 memory growth | Soak tests, bounded caches, watchdog restarts |

## Implementation notes

- H.264 and AV1 play on Android. HEVC 10-bit HDR10 fails with the stock media_kit Android build;
  those files use the Immich playback-stream fallback.
- HEIC uses libheif; AVIF and RAW require the native decoder build.
- Desktop CEF transparency and input are provided by the pinned `webview_cef` fork.
- Android plugins require Chromium 100+. Older WebViews disable plugins and their overlays.
- Linux CEF runtime performance is not validated.
