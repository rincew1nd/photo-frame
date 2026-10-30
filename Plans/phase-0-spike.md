# Phase 0 — Technical Spike

Status: Done (conditional go; see delivery log and `Docs/spike-0-results.md`)
Type: Time-boxed go/no-go spike
Estimated effort: 2–3 days
Depends on: none
Blocks: Phase 1 (production scaffold), Phase 4 (plugin implementation)

## Goal

Prove the two hardest parts of the chosen stack before investing in production code:

1. Original media can be decoded/played with audio on Windows, Linux x64, and Android.
2. A transparent, interactive HTML plugin overlay can sit above video and below Flutter controls,
   with host-mediated sandboxing and movement.

The spike is a throwaway Flutter project or branch. Do not build product architecture around it
until the exit criteria pass.

## Questions to answer

- Does `webview_cef` support transparent offscreen rendering on Windows and Linux, and can it be
  patched if not?
- Can CEF webviews receive input and be moved/resized while a video texture plays underneath?
- Can Flutter controls/dialogs reliably render and receive input above Android plugin webviews?
- Does `media_kit` decode HEVC 10-bit HDR/HLG, AV1, and H.264 originals with audio on all targets?
- How good is HDR-to-SDR tone-mapping?
- Do libheif and LibRaw decode HEIC, AVIF, DNG, and ProRAW acceptably on the target hardware?
- Can a local loopback server + sandboxed iframe + CSP + native request interception provide the
  intended plugin sandbox and network policy?
- Are per-instance small plugin webviews performant enough on Linux software OSR?
- Do keep-awake/startup hooks work on all three targets?

## Environment

| Platform | Reference |
|---|---|
| Windows | Windows 10/11 x64 |
| Linux | Ubuntu 24.04 x64, X11; repeat on Wayland if available |
| Android | API 26 low-end tablet and a modern API 34+ device; arm64 and armeabi-v7a where possible |

Record OS, GPU/driver, WebView/CEF version, Flutter version, libmpv version, and test file details
for every measurement.

## Tasks

### 1. Flutter spike scaffold

- Create a minimal Flutter app for Windows/Linux/Android.
- Add media_kit + libmpv.
- Add webview_cef and webview_flutter.
- Add libheif/LibRaw FFI prototypes or a minimal wrapper.
- Add a local HTTP server prototype and a sandboxed iframe host page.

### 2. Original media playback

- Play local H.264/AAC and HEVC 10-bit HDR/HLG files; add AV1 if a sample is available.
- Verify audio output, mute, seek/loop, pause/resume.
- Verify tone-mapping visually and record CPU/GPU usage.
- Test 1080p and 4K where hardware supports it.
- Confirm media_kit can add Immich-style `x-api-key` headers to an HTTP media request.
- Capture results for each platform.

### 3. Stills

- Decode HEIC (8/10-bit), AVIF, DNG, and a ProRAW sample.
- Measure time and memory; verify preview-first and display-sized conversion.
- Verify the resulting image looks acceptable (tone-mapping/color).
- Test fallback when a format is unsupported.

### 4. Transparent CEF overlay (Windows/Linux)

- Render a video texture/layer.
- Add a small transparent CEF webview with a clock and a button above it.
- Verify alpha, no black/white box, and correct z-order.
- Verify mouse clicks reach the webview; clicks outside pass through to Flutter.
- Add a Flutter button/dialog above the webview; verify draw order and input.
- Request a placement change from the plugin; verify the webview moves/resizes and persists.
- Add an external link and verify interception/confirmation.
- Measure Linux OSR CPU cost at 1080p for small and full-screen webviews.
- If transparency is not exposed by `webview_cef`, patch the CEF window/background settings and
  retest. Record the patch scope.

### 5. Android overlay

- Play a video with media_kit; add a transparent WebView with a clock/button above it.
- Verify transparency, input, and placement.
- Add Flutter controls/dialogs above it. Verify z-order and input.
- If controls cannot render above, prototype the fallback: hide plugin webviews while
  controls/dialogs are open.
- Check behavior on the API 26 device’s system WebView version; record the baseline.

### 6. Plugin host sandbox

- Serve a trusted host page and plugin assets from `127.0.0.1` with a random token.
- Load the plugin in a sandboxed iframe (opaque origin).
- Bridge state at 1 Hz and receive a button action.
- Verify direct `fetch`/external images are blocked.
- Verify host-proxied network works when enabled and is blocked by default.
- Verify plugin cannot read host storage/cookies.
- Verify a hanging/throwing plugin does not block the video or app controls.
- Test external link interception and blocked navigation/popups.

### 7. Platform hooks

- Keep-awake/display-sleep prevention on Windows, Linux, Android.
- Minimal start-on-boot/autostart on each target.
- Single-instance check on desktop.
- Verify safe-area/inset reporting on Android.

### 8. Requirements alignment

- Apply the agreed requirement edits: new app ID, API 26, no Pi/iOS/macOS, HDR SDR,
  plugin ZIP/format/permissions, no legacy migration, MIT license.
- Record any spike-driven deviation in the ADR and requirements alignment document.

## Go/no-go criteria

Go if all of the following hold:

- H.264, HEVC, and AV1 originals play with audio on the tested platforms; HDR is tone-mapped
  acceptably.
- HEIC/AVIF/DNG/ProRAW decode at an acceptable speed and memory level; fallbacks work.
- Transparent CEF overlay works on Windows and Linux, including input and a Flutter control above.
- Android transparent WebView overlay works with input; controls z-order works or the documented
  fallback is acceptable.
- Plugin sandbox/network/storage isolation behaves as designed.
- Linux OSR performance is acceptable with small per-plugin webviews at 1 Hz.
- Keep-awake/startup hooks are feasible.

No-go triggers:

- CEF transparency cannot be achieved on a supported desktop target.
- Android cannot display controls above plugin webviews and the hidden-overlay fallback is
  unacceptable.
- Original codecs cannot be decoded acceptably on a supported target.
- Plugin isolation cannot be enforced without exposing host credentials/data.

## Fallbacks if a criterion fails

| Failure | Response |
|---|---|
| CEF transparency/input | Patch webview_cef; if unsupported, evaluate KCEF/JCEF or a different desktop UI stack |
| Android z-order | Hide plugin webviews while controls/dialogs are open; validate UX |
| Linux OSR performance | Per-plugin small webviews, lower OSR rate, limit plugin count; if still unacceptable, re-evaluate Linux plugin support |
| Codec missing | Adjust FFmpeg/libmpv build; Immich transcode fallback as last resort |
| ProRAW quality | Embedded preview fallback; document limitation |
| WebView baseline | Raise Android minimum for plugins or disable plugins on old devices |

## Deliverables

- Spike project/branch (not shipped; the project was removed after results capture).
- `Docs/spike-0-results.md` with measurements, screenshots, and decisions.
- Updated `Docs/ADR-0001-stack.md` if the decision changes.
- Requirements alignment applied to `REQUIREMENTS.md` and the Docs set.
- Notes for Phase 1 and Phase 4.
- Any required `webview_cef` patch recorded and reproducible.

## Out of scope

- Production UI, navigation, settings, cache, real Immich integration.
- Full plugin API, install UI, reference plugins.
- Release packaging/signing.
- Pi/iOS/macOS.

## Acceptance checklist

- [ ] Windows original media + audio + tone-mapping verified.
- [ ] Linux original media + audio + tone-mapping verified.
- [ ] Android original media + audio + tone-mapping verified.
- [ ] HEIC/AVIF/DNG/ProRAW decode verified with measurements.
- [ ] Windows CEF transparent overlay + input + controls above verified.
- [ ] Linux CEF transparent overlay + input + performance verified.
- [ ] Android WebView overlay + input + z-order/fallback verified.
- [ ] Plugin sandbox/network/storage/link policy verified.
- [ ] Keep-awake/startup/single-instance hooks verified. (Wakelock verified; startup/single-instance deferred.)
- [x] Requirements alignment applied to REQUIREMENTS.md and Docs.
- [x] Go/no-go decision recorded.

Remaining unchecked items are recorded in `Docs/spike-0-results.md` as environment gaps or blockers
(no Linux host, HEVC/AVIF/RAW decoder gaps, desktop CEF runtime/transparency, modern Android WebView).
The conditional go permits Phase 1 and the photo-only Phase 2; Phase 3/4 work remains gated.

## Delivery log

| Date | Result | Notes |
|---|---|---|
| 2026-10-27 | Conditional go | Windows/Android H.264 and Android AV1 playback verified; HEVC 10-bit HDR10 failed on Android; HEIC pass, AVIF/libheif/LibRaw missing; sandbox CSP/postMessage verified; Android overlay only composites with Impeller off and HTML was blank on WebView 12.1.2.326; desktop CEF built but transparency is not exposed; Linux not executed. Requirements alignment applied. See `Docs/spike-0-results.md`. |
