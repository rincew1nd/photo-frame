# Photo Frame Documentation

Technical documentation for Photo Frame, a full-screen photo frame for a self-hosted Immich
library. Product requirements live in [`../REQUIREMENTS.md`](../REQUIREMENTS.md).

## App identity

| Item | Value |
|---|---|
| Display name | Photo Frame |
| Application ID / namespace | `com.rincew1nd.photoframe` |
| Version | `1.0.0` |
| Platforms | Windows 10/11 x64, Linux x64, Android 8.0+ (API 26) |
| Out of scope | iOS, macOS, Raspberry Pi / Linux ARM64, true HDR output |
| License | MIT |

## Documentation map

| Document | Contents |
|---|---|
| [`architecture.md`](architecture.md) | Stack, layers, runtime architecture, repository layout, data flow |
| [`media.md`](media.md) | Video, audio, stills, Live Photos, HDR policy, format support, fallbacks |
| [`plugins.md`](plugins.md) | Plugin bundle, manifest, host, sandbox, JS API, placement, lifecycle, limits |
| [`plugin-author-guide.md`](plugin-author-guide.md) | Manifest, settings, host API v1, limits, and example starting points |
| [`data-cache.md`](data-cache.md) | Immich API/auth, cache/offline, settings, database, sync |
| [`platforms.md`](platforms.md) | Windows, Linux x64, Android behaviour, startup, kiosk, packaging |
| [`security.md`](security.md) | Threat model, secrets, plugin sandbox, local server, updates |
| [`licensing.md`](licensing.md) | MIT app license, third-party licenses, LGPL/CEF obligations, patents |
| [`testing-ci.md`](testing-ci.md) | Test strategy, media fixtures, CI, build, and release commands |
| [`ADR-0001-stack.md`](ADR-0001-stack.md) | Stack decision record and alternatives |

## Conventions

- **MUST / SHOULD / MAY** follow the meaning in `REQUIREMENTS.md`.
- **Host** means the Flutter application.
- **Plugin** means an installed HTML/CSS/JS bundle.
- **Original** means the unmodified Immich asset file, not a preview or server transcode.
- **Desktop** means Windows x64 and Linux x64.
- **Android** means API 26 and later.
- **V1** excludes iOS, macOS, Pi/ARM64, true HDR output, a plugin marketplace, and plugin
  signatures.

## Stack

- Flutter with Riverpod state management and go_router navigation.
- Dio for the Immich API, using `x-api-key` or OAuth bearer tokens.
- Drift/SQLite for metadata and plugin state.
- libmpv through media_kit for video and audio.
- libheif and LibRaw through `dart:ffi` for HEIC/HEIF/AVIF and DNG/RAW stills.
- CEF through the patched `webview_cef` fork on desktop, and the system WebView on Android, for
  plugin overlays.
- OS secure storage for the Immich API key and OAuth tokens.

See [`architecture.md`](architecture.md) for the full design and [`ADR-0001-stack.md`](ADR-0001-stack.md)
for the decision record.
