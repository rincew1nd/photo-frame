# Requirements Alignment

Status: Applied in Phase 0 (2026-10-27)
Source: [`../REQUIREMENTS.md`](../REQUIREMENTS.md)
Related: [`architecture.md`](architecture.md), [`plugins.md`](plugins.md), [`platforms.md`](platforms.md)

`REQUIREMENTS.md` now applies to the cross-platform application
(`com.rincew1nd.photoframe`). This document records the decisions that change or reinterpret the
original Android-only requirements. The Phase 0 requirements update has been applied; this
document remains the decision record.

## 1. Product identity

| Requirement context | New decision |
|---|---|
| Applies to `com.dav3.immichframe` | New app: `com.rincew1nd.photoframe` |
| Existing Android app | Remains a separate product; no data sharing |
| Upgrade behaviour | Fresh install; no migration |
| Display name | “Photo Frame” placeholder |

### Required changes

- Replace the “Applies to” line with `com.rincew1nd.photoframe`.
- Remove the legacy upgrade mapping in **MR-04** (“Skip Videos” → type filter). New installs use
  the fresh-install defaults: Photos, Live Photos, and Videos enabled.
- Remove any assumption that existing settings or cache are available.
- Keep all feature-level acceptance scenarios that do not depend on migration.

## 2. Platform scope

| Platform | V1 status |
|---|---|
| Windows 10/11 x64 | Supported |
| Linux x64 (Ubuntu/Debian) | Supported |
| Android 8.0+ (API 26) | Supported |
| iOS | Out of scope |
| macOS | Out of scope |
| Raspberry Pi / Linux ARM64 | Out of scope |
| True HDR output | Out of scope; tone-mapped SDR |

### Required changes

- Section 7 “Out of Scope”: add macOS, Raspberry Pi/ARM64, and true HDR output; iOS is already
  listed.
- Replace Android-only wording in shared requirements with platform-neutral wording plus a
  platform applicability table.
- **NFR-07**: replace Android 6.0/API 23 with Android 8.0/API 26. Add the WebView baseline and
  graceful plugin degradation.
- Define desktop equivalents for Android-only requirements (see section 6).

## 3. Media and HDR

The product uses original files wherever the bundled decoders support them.

- Video/audio: libmpv/FFmpeg.
- Stills: Flutter decoders, libheif (HEIC/HEIF/AVIF), LibRaw (DNG/ProRAW).
- HDR/10-bit: decode and tone-map to SDR. HDR10+ dynamic metadata and Dolby Vision are not
  supported. The app must not claim HDR output.
- Unsupported or corrupt originals fall back to the Immich preview/playback stream and log.
- RAW is limited to DNG and ProRAW for v1; other camera RAW formats are not required.

### Required changes

- Add an explicit HDR limitation/acceptance note.
- Add a supported-format matrix and fallback rule.
- Clarify that “Play originals” does not guarantee every codec, only those in the bundled decoder
  matrix with a graceful fallback.

## 4. Plugins

The plugin system is specified in [`plugins.md`](plugins.md). Phase 4 has not started, so it is not
implemented or verified.

### Resolved open questions from REQUIREMENTS.md

| Open question | V1 decision |
|---|---|
| Plugin scripts: sandboxed JS vs declarative language | Sandboxed HTML/CSS/JS |
| Distribution: file, URL, catalog | Local ZIP import only |
| Signatures/checksums required | No signatures in v1; explicit install + permission consent; record SHA-256 |
| Plugins outside the slideshow | Slideshow only in v1 |
| Bundle/memory/CPU/instance limits | 20 MB ZIP, 100 MB extracted, 500 files, 20 installed, 10 active, API v1 (see `plugins.md`) |
| Replace built-in overlays with plugins | All overlays are bundled plugins; clock/weather/metadata are enabled by default and migrated from the compiled overlay settings |
| Plugin format | Sandboxed HTML/CSS/JS in the plugin webview; Dart is not loaded at runtime |
| Plugin placement | Drag-and-drop and resize with optional grid snap/grid size in the Plugins screen |
| Plugin settings | Each installed plugin has its own schema-rendered settings screen |
| Plugin write access to playback | Yes, declared actions, user-granted, rate-limited |
| Network domain allowlist | No allowlist in v1; network is host-proxied and permission-gated |

### Required changes

- Add ZIP bundle layout, manifest fields, description, screenshots, permissions, and install UI.
- Add interactive plugin requirements: buttons, links, text input where supported, programmatic
  placement.
- Add host-mediated network/storage/actions and the “no direct Immich access” rule.
- Add plugin API versioning and WebView baseline.
- Resolve the existing open questions as listed above.
- Keep **PLG-10** (multiple instances) as MAY; v1 does not implement multiple instances per plugin.

## 5. Plugin security clarifications

- Plugins run in a sandboxed iframe inside a per-instance transparent webview.
- Plugin assets come from a loopback server with an ephemeral token.
- CSP and native request interception block external network unless the Network permission is
  granted; granted network goes through the host proxy.
- Plugins never receive the API key, server URL, album list, or library metadata outside the
  snapshot.
- Plugin storage is host-managed and removed on uninstall.
- External links open in the system browser with confirmation; all other navigation is blocked.
- A failed plugin is hidden/disabled without affecting the slideshow.

## 6. Android-only requirements and desktop equivalents

| Requirement | Android | Windows/Linux desktop |
|---|---|---|
| BR-07 biometric/device credential | BiometricPrompt / device credential where a lock exists | Windows Hello if available; Linux fail-open (no standard equivalent) |
| BR-09 night mode | Window brightness | Black overlay dimming; no universal panel-brightness API |
| BR-10 start-on-boot | Boot receiver + HOME/launcher role | Windows startup entry; Linux XDG autostart/systemd user service |
| BR-10 launcher mode | Home replacement role | Kiosk/fullscreen mode; no OS launcher replacement concept |
| BR-10 GitHub update check | Download + install APK | Check GitHub release; open/download artifact; self-update where packaging permits |
| BR-12 keep screen on | `FLAG_KEEP_SCREEN_ON` / wakelock | OS sleep/display inhibit (`SetThreadExecutionState`, logind/DBus) |
| BR-12 OLED burn-in | Photo motion/pan | Photo motion/pan still applies; OLED burn-in is device-specific |
| BR-12 cutouts/system insets | Window insets/safe areas | Safe area is zero unless the OS reports one; plugins still use safe-area API |
| NFR-07 API floor | API 26+; WebView baseline | CEF 149 on desktop; system WebView on Android |

## 7. Performance and reliability

- NFR-02: plugin updates at 1 Hz must not cause visible slideshow frame drops. Use per-instance
  small webviews, coalesced state, low OSR frame rate, and no plugin work on the media path.
- NFR-03: 72-hour soak tests on Windows, Linux, and Android; bounded caches; watchdog restarts.
- NFR-07: plugins degrade when WebView is unavailable or below baseline; because all overlays are
  plugins, the slideshow continues without overlays on those devices.
- NFR-09: plugins never call Immich directly; the host snapshot is the only data source.

## 8. Settings and UI

- Settings groups and summaries follow SET-01..SET-09.
- Per-aspect profiles and filters live in the designated group.
- Plugin management, per-plugin settings, permissions, icons/screenshots, and placement live in the
  Plugins group. Clock, weather, and metadata are managed there as bundled plugins.
- Settings changes apply without restart.
- Onboarding tour targets survive the new groups.
- Search (SET-08) remains MAY; not required for v1.

## 9. Localization

- BR-13 remains MUST for the app's supported locales.
- V1 localization infrastructure uses ARB files with English fallback.
- The final supported locale list is an open product decision. Porting the existing app’s
  translations is optional and must be recorded before release.

## 10. Licensing and legal

- App license: MIT (see [`licensing.md`](licensing.md)).
- Include third-party notices and LGPL dynamic-linking compliance.
- Do not ship GPL-only codec features.
- HEVC patent licensing is a separate legal question; document before commercial distribution.
- Do not claim Dolby Vision or true HDR support.

## 11. Open product decisions

These do not block the architecture or Phase 0:

- Final display name and branding.
- Final supported locale list.
- Desktop installer formats (Windows installer/ZIP; Linux AppImage/deb).
- Final app icon and visual identity.
- Plugin limit values (defaults proposed in `plugins.md`).
- Windows Hello behaviour and Linux biometric fallback.
- Desktop update UX (check only vs download/replace where packaging permits).
- Whether multiple plugin instances per plugin are added after v1.

## 12. Requirements update checklist (Phase 0)

- [x] Replace package name and applies-to line.
- [x] Update the related-docs header to point at `Docs/README.md` (the legacy
      `docs/functional-spec.md` / `docs/technical-spec.md` / `docs/ui-spec.md` paths do not exist in
      this repository).
- [x] Remove MR-04 legacy upgrade mapping.
- [x] Change NFR-07 to API 26; add WebView baseline.
- [x] Add platform applicability table and desktop equivalents.
- [x] Add HDR SDR limitation.
- [x] Add supported media matrix and fallback policy.
- [x] Add plugin ZIP format, metadata, screenshots, permissions, interactivity, and movement.
- [x] Resolve plugin open questions.
- [x] Add plugin security and network mediation.
- [x] Add plugin API versioning and failure isolation.
- [x] Update NFR-02/NFR-03 with plugin and soak targets.
- [x] Add no-Pi/macOS/ARM64 and no-true-HDR to out-of-scope.
- [x] Record the MIT license and third-party notice requirement.
