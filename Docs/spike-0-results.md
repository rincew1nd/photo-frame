# Phase 0 Spike Results

Status: Complete as a time-boxed spike; conditional go recorded
Date: 2026-10-27
Spike project: removed after results capture; this document and `evidence/` are the surviving record.
Related: [`ADR-0001-stack.md`](ADR-0001-stack.md), [`requirements-alignment.md`](requirements-alignment.md)

## 1. Scope and environment

The spike answered the Phase 0 questions with a disposable Flutter app containing media, still-image,
overlay, sandbox, and platform-hook probes. It is not production architecture.

| Item | Value |
|---|---|
| Flutter | 3.47.8 stable, Dart 3.13.7 |
| Windows host | Windows 11 25H2, x64, Visual Studio Build Tools 17.14, Windows SDK 10.0.26100 |
| Android reference | Huawei AGS3K-W09 (Kirin 710), Android 10 / API 29, arm64, 1920x1200 @ 320 dpi |
| Android WebView | Huawei WebView 12.1.2.326 (version code 4703, target SDK 31); Chrome 107 is installed but is not a valid WebView provider (signature mismatch) |
| Linux host | Not available in this environment; no Linux run or build was executed |
| media_kit | 1.2.6, media_kit_video 2.0.1, libs 1.0.7 (Android 1.3.8, Windows 1.0.11) |
| webview_flutter | 4.14.1 (Android 4.14.1) |
| webview_cef | 0.6.2, CEF 149.0.4+g2f1bfd8 / Chromium 149.0.7827.156 |
| Flutter rendering | Impeller on = default; Impeller off tested as a platform-view diagnostic |

Media fixtures were generated locally with FFmpeg and are not committed as large binaries. The
fixtures were removed with the spike project.

| Fixture | Streams |
|---|---|
| `h264_aac.mp4` | H.264 1280x720 8-bit + AAC 48 kHz mono, 3 s |
| `hevc_hdr10.mp4` | HEVC Main 10, 1280x720, BT.2020 / SMPTE ST 2084 (HDR10) + AAC, 3 s |
| `hevc_hlg.mp4` | HEVC Main 10, 1280x720, BT.2020 / ARIB STD-B67 (HLG) + AAC, 3 s |
| `av1.mp4` | AV1 640x360 8-bit, 2 s |
| `sample.heic` / `.avif` | 800x600 stills encoded with pillow-heif / pillow-avif |
| `sample.png/.webp/.gif` | Decoder probes |

The user requested that the spike not play audible sound. All subsequent probes were run muted
(`volume 0`); audio tracks were confirmed in the media files, but audible output was not exercised.

## 2. Results

### 2.1 Original media playback

| Check | Windows | Android API 29 | Result |
|---|---|---|---|
| H.264/AAC originals | Build and launch succeeded; `Playing: true`, duration 0:03, controls responsive. PrintWindow cannot capture a Flutter texture, so the captured video area is black. | Plays; test pattern visible, position advanced, loop/seek/pause controls responded. `Error: none`. | PASS (video); audio not audible by request |
| AV1 | Not measured | Plays; test pattern visible, position advanced. Software decode. | PASS |
| HEVC 10-bit HDR10 | Not measured | Fails with `Error: Could not open codec` using the default hardware path; retry with `enableHardwareAcceleration: false` still showed no frame and position 0:00. | FAIL on Android reference |
| HEVC 10-bit HLG | Not measured | Not separately exercised after the HDR10 failure; the shared 10-bit HEVC decoder failure is expected to apply. | NOT VERIFIED / likely FAIL |
| Audio output | Not audible by request | Not audible by request; AAC track present and volume 0 | Limited evidence |
| media_kit `x-api-key` headers | `Media(..., httpHeaders: {'x-api-key': 'secret'})` preserves the header; unit test green. | Same API path. | PASS at API level |
| Tone-mapping quality | Not measured | Not reached because HDR10 decode failed | FAIL / not measured |

The Android HEVC result is a **Phase 3 blocker** for the stock media_kit Android build. The documented
fallbacks are a custom libmpv/FFmpeg build with the required HEVC decoder or an Immich
transcode/playback stream. H.264 and AV1 remain usable, and Phase 2 is photo-only.

### 2.2 Still images

| Format | Android API 29 | Notes |
|---|---|---|
| PNG / WebP / animated GIF | PASS | Flutter built-in decoders |
| HEIC 8-bit | PASS | Android ImageDecoder decoded the fixture; this is device/API-dependent |
| AVIF | FAIL | `Invalid image data`; no AVIF decoder in the system path |
| libheif | MISSING | `dlopen failed: library "libheif.so" not found` |
| LibRaw | MISSING | `dlopen failed: library "libraw.so" not found` |
| DNG / ProRAW | NOT TESTED | Requires a built LibRaw and legal fixture |

The production still pipeline therefore needs libheif and LibRaw for AVIF and RAW. HEIC cannot rely on
the platform decoder alone across the API range.

### 2.3 Transparent overlays and z-order

Android:

- With Impeller enabled (default), the transparent `webview_flutter` platform view was present in the
  UI hierarchy at the expected bounds but was not visible above the media_kit video or even above a
  plain Flutter background. Flutter controls rendered correctly above the webview box.
- With Impeller disabled (`io.flutter.embedding.android.EnableImpeller=false`), the webview was
  composited above the video as a transparent dark box, proving the z-order/transparency path is
  viable, but the HTML content remained blank. A local `127.0.0.1` host page and an inline opaque
  page both failed to render. The Huawei WebView is below the proposed Chromium 100+ baseline.
- The Flutter controls/dialog layer rendered above the webview box. The "hide webview while Flutter
  controls are open" fallback is implemented in the spike.
- This device cannot validate modern-WebView plugin rendering. The production rule is to gate plugins
  on WebView baseline 100+ and keep built-in Flutter overlays available on older devices.

Windows/Linux CEF:

- The Windows build succeeded with `webview_cef` 0.6.2 and CEF 149. It required the documented
  `windows/runner/main.cpp` hooks and a ~330 MB CEF download; the first build took ~272 s.
- `webview_cef` exposes no transparency/background-color API. Its texture is opaque by default. A
  transparency patch or a different OSR compositing approach is still required before relying on it
  for transparent plugin overlays. Runtime overlay capture was not completed on Windows.
- Linux was not executed. The CEF software OSR performance question remains open.

**Findings:** the transparent overlay layer is the highest remaining risk. The Android reference
device cannot demonstrate modern plugin rendering, and desktop CEF transparency is not exposed by the
current plugin. Phase 4 must not start until this is resolved or the fallback UX is accepted.

### 2.4 Plugin sandbox

The loopback host/plugin sandbox was exercised through the Android app's server, forwarded to the
desktop with `adb forward tcp:8080 tcp:35535`, and loaded in Chrome 155:

- The host page served from `127.0.0.1` with a random 32-hex token and strict CSP.
- The plugin ran in `<iframe sandbox="allow-scripts">` (no `allow-same-origin`).
- `ready`, `fetchResult`, and `buttonClick` messages reached the host via `postMessage`.
- Direct plugin `fetch` to the local secret path and to `example.com`/`google.com` was blocked by
  `connect-src 'none'` (six CSP console errors, no successful network responses).
- `secret.txt` returned 403 without `x-spike-token`, 200 with it; wrong token and traversal returned
  404. Server tests cover the same cases.
- Plugin/host isolation and the network policy are **validated in a modern browser**. WebView
  rendering on the old Huawei WebView remains the device-specific limitation above.

### 2.5 Platform hooks

- Android: `wakelock_plus` enable/disable worked; `Wakelock enabled: true` and the OS wake-lock
  summary was active while held. Autostart, single-instance, and safe-area reporting were not
  implemented in the spike; they remain Phase 1/5 work.
- Desktop: single-instance and autostart were not implemented in the spike.
- The production platform-service interfaces and stubs are Phase 1 deliverables.

### 2.6 Build and tooling

- Android debug APK built and installed on the reference device.
- Windows debug build succeeded (`build/windows/x64/runner/Debug/photo_frame_spike.exe`).
- Flutter's Windows plugin symlink requirement exposed a host limitation (Developer Mode off and
  the project, pub cache, and SDK on different drives). The local Flutter tool was given a junction
  fallback and `PUB_CACHE` was moved to the project drive for verification. Developers should enable
  Developer Mode or keep the project and pub cache on the same volume; production CI must use a
  supported configuration.
- Linux build/run was not executed.

## 3. Decisions

### Go

- **Phase 1 foundation and Phase 2 photo slideshow:** go. They do not depend on HEVC or plugin
  overlays; H.264 thumbnails and the built-in JPEG/PNG/WebP/GIF decoders are sufficient for the
  photo-only scope.
- **Sandbox design:** go for the loopback host + sandboxed iframe + CSP + postMessage model, subject
  to native request interception for WebView/CEF in Phase 4.
- **Storage and settings design:** go; these are standard Flutter/Drift/secure-storage paths.

### Conditional / no-go

- **HEVC 10-bit HDR/HLG originals on Android:** no-go with the stock media_kit Android build. Phase 3
  must either pin/build libmpv with HEVC support or implement the Immich transcode fallback and record
  it in diagnostics. Do not claim full original-codec support until this passes.
- **AVIF/DNG/ProRAW stills:** no-go until libheif/LibRaw are built and tested. HEIC is device-dependent
  and must not be the only path.
- **Transparent plugin overlays:** conditional no-go for Phase 4. Android reference WebView is below
  baseline and renders blank; desktop CEF has no exposed transparency API in `webview_cef` 0.6.2.
  Resolve transparency (patch CEF/OSR or evaluate another host) and validate on a modern Android
  WebView before production plugin work. The agreed fallback is to disable plugins below the Android
  WebView baseline while keeping built-in overlays.
- **Linux:** not verified. Performance, transparency, and Wayland/X11 startup remain open.

### Architecture impact

No stack change. `ADR-0001` remains accepted. The findings add implementation constraints:

1. Phase 3 must treat HEVC/HLG as a decoder-build problem with an Immich fallback.
2. Phase 4 must prove desktop CEF transparency and modern Android WebView rendering before building the
   plugin host; otherwise plugins remain disabled on unsupported devices.
3. The Windows build pipeline must enable plugin symlink support or use a same-volume pub cache.
4. Impeller/platform-view composition can affect WebView visibility; the production app must test on
   the reference devices and avoid relying on transparent platform views until proven.

## 4. Phase 0 acceptance checklist

| Item | Status |
|---|---|
| Windows original media + audio + tone-mapping verified | Partial: build/playback state verified; texture capture and HEVC/tone-map not verified; audio muted by request |
| Linux original media + audio + tone-mapping verified | Not executed (no Linux host) |
| Android original media + audio + tone-mapping verified | Partial: H.264/AV1 play; HEVC HDR10 fails; audio muted by request |
| HEIC/AVIF/DNG/ProRAW decode verified with measurements | Partial: HEIC PASS, AVIF FAIL, libheif/LibRaw missing, DNG/ProRAW not tested |
| Windows CEF transparent overlay + input + controls above verified | Build verified; transparency/input runtime not verified |
| Linux CEF transparent overlay + input + performance verified | Not executed |
| Android WebView overlay + input + z-order/fallback verified | Partial: z-order only with Impeller off; HTML blank on old WebView; fallback implemented |
| Plugin sandbox/network/storage/link policy verified | Yes for loopback/CSP/postMessage in Chrome; native interception pending Phase 4 |
| Keep-awake/startup/single-instance hooks verified | Keep-awake PASS; startup/single-instance not implemented |
| Requirements alignment applied to REQUIREMENTS.md and Docs | Yes |
| Go/no-go decision recorded | Yes (conditional go for Phases 1–2; no-go/conditional for HEVC, stills, overlays, Linux) |

## 5. Evidence

Screenshots and logs are under [`evidence/`](evidence/):

- `android-h264-playback.png` — H.264 playback on the API 29 device.
- `android-hevc-hdr10-fail.png` — HEVC HDR10 failure.
- `android-stills-probe.png` — HEIC PASS, AVIF FAIL, libheif/LibRaw missing.
- `android-overlay-impeller-off.png` — transparent webview composited above video (HTML blank).
- `android-wakelock.png` — wakelock probe.
- `windows-media-playback.png` — Windows playback state (texture not captured by PrintWindow).
- Sandbox evidence: CSP console errors, host postMessage output, and 403/200/404 probe results are
  summarized in section 2.4; the spike's unit tests were removed with the project.

## 6. Notes for later phases

- Phase 1: use the same app identity, secure-storage abstraction, and platform-service interfaces;
  do not copy the spike's screens. Test WebView version gating and the Windows symlink/pub-cache setup.
- Phase 2: photo-only scope is safe. Keep HEIC/AVIF/RAW behind the still pipeline interfaces even
  though Phase 2 uses built-in formats.
- Phase 3: resolve HEVC 10-bit and tone-mapping before claiming original playback; add the Immich
  playback-stream fallback and diagnostics.
- Phase 4: do not build the plugin host against the blank-webview reference. Validate CEF
  transparency and a Chromium 100+ Android WebView; otherwise ship built-in overlays only.
