# Photo Frame Documentation

Status: Draft v0.1
Last updated: 2026-10-27
Source of truth for product requirements: [`../REQUIREMENTS.md`](../REQUIREMENTS.md)

`REQUIREMENTS.md` has been aligned in Phase 0 to the new application identity and Docs set. Functional
and UI requirements remain in `REQUIREMENTS.md`; this Docs set replaces the technical spec. The
alignment checklist and resolved decisions are recorded in
[`requirements-alignment.md`](requirements-alignment.md).

This folder documents the technical stack, architecture, and implementation decisions for the
cross-platform photo frame application. Phase plans are in [`../Plans/README.md`](../Plans/README.md).

## App identity

| Item | Value |
|---|---|
| Display name | Photo Frame (placeholder until branding is final) |
| Application ID / namespace | `com.rincew1nd.photoframe` |
| Initial version | `1.0.0 (1)` |
| Install model | Fresh install. No migration from `com.dav3.immichframe`. |
| Platforms | Windows 10/11 x64, Linux x64, Android 8.0+ (API 26) |
| Out of scope for v1 | iOS, macOS, Raspberry Pi / Linux ARM64, true HDR output |
| License | MIT |

The existing Android app remains a separate product. The new application does not share its
package, signing key, settings, or cache.

## Locked decisions

- Greenfield **Flutter** application; one codebase for Windows, Linux x64, and Android.
- Direct Immich API communication; no intermediary server.
- Originals are used for playback wherever the bundled decoders support them.
- Video and audio use **libmpv via media_kit**; stills use Flutter codecs plus **libheif** and
  **LibRaw**.
- HDR/10-bit originals are decoded and **tone-mapped to SDR**. True HDR output is out of scope.
- Plugins are HTML/CSS/JS bundles installed from a local ZIP. They are interactive, sandboxed,
  movable, and able to display descriptions and screenshots in the install UI.
- Plugin rendering uses a transparent webview per instance: **CEF via webview_cef** on desktop and
  the **system WebView** on Android.
- Plugin network access, storage, and app actions are mediated by the host. Plugins never receive
  the Immich API key, server URL, or library data.
- MIT license with third-party notices and LGPL dynamic-linking compliance.

## Documentation map

| Document | Contents |
|---|---|
| [`architecture.md`](architecture.md) | Stack, layers, runtime architecture, repository layout, data flow |
| [`media.md`](media.md) | Video, audio, stills, Live Photos, HDR policy, format support, fallbacks |
| [`plugins.md`](plugins.md) | Plugin bundle, manifest, host, sandbox, JS API, placement, lifecycle, limits |
| [`data-cache.md`](data-cache.md) | Immich API/auth, cache/offline, settings, database, sync |
| [`platforms.md`](platforms.md) | Windows, Linux x64, Android behaviour, startup, kiosk, packaging |
| [`security.md`](security.md) | Threat model, secrets, plugin sandbox, local server, updates |
| [`licensing.md`](licensing.md) | MIT app license, third-party licenses, LGPL/CEF obligations, patents |
| [`testing-ci.md`](testing-ci.md) | Test strategy, media fixtures, soak tests, CI/build/release |
| [`requirements-alignment.md`](requirements-alignment.md) | Required edits and interpretation of REQUIREMENTS.md |
| [`phase-1-2-verification.md`](phase-1-2-verification.md) | Phase 1/2 automated, real-server, build, and soak evidence |
| [`ADR-0001-stack.md`](ADR-0001-stack.md) | Stack decision record and alternatives |
| [`../Plans/README.md`](../Plans/README.md) | Phase overview and sequencing |

## Planning model

Implementation is split into phases. Each phase has a goal, scope, deliverables, exit criteria, and
known risks.

| Phase | Focus | Gate |
|---|---|---|
| 0 | Technical spike | Go/no-go on media, transparent overlays, Android z-order, decoders |
| 1 | Foundation | Immich connection/auth, settings, storage, CI |
| 2 | Photos and cache | Slideshow, offline cache, filters, per-aspect profiles |
| 3 | Media | Video, Live Photos, audio, HEIC/AVIF, DNG/ProRAW, tone-mapping |
| 4 | Plugins | ZIP install, sandbox, host bridge, placement, actions, reference plugins |
| 5 | Platform integration | Boot/launcher, kiosk, sleep prevention, biometrics, updates |
| 6 | Hardening and release | Soak, security, performance, docs, signed artifacts |

## Conventions used in these documents

- **MUST / SHOULD / MAY** follow the meaning in `REQUIREMENTS.md`.
- **Host** means the Flutter application.
- **Plugin** means an installed HTML/CSS/JS bundle.
- **Original** means the unmodified Immich asset file, not a preview or server transcode.
- **Desktop** means Windows x64 and Linux x64.
- **Android** means API 26 and later.
- **V1** excludes iOS, macOS, Pi/ARM64, true HDR output, a plugin marketplace, and plugin
  signatures.

## Known limitations

- True HDR output is not supported. HDR10/HLG video and 10-bit stills are tone-mapped to SDR.
  HDR10+ dynamic metadata and Dolby Vision are not supported.
- Streaming a full-screen transparent CEF overlay on Linux uses a software readback path. Plugin
  instances are kept small and update at low frequency.
- Android plugin support depends on the system WebView version. Built-in overlays continue to work
  when plugins are unavailable.
- Phase 0 found that `webview_cef` 0.6.2 exposes no transparent-background API, and the reference
  Android WebView (12.1.2.326) rendered the transparent overlay blank. CEF transparency and modern
  Android WebView rendering remain gates for Phase 4; built-in overlays are the fallback.
- HEVC 10-bit HDR10 failed on the stock Android media_kit build in Phase 0. Phase 3 needs a custom
  libmpv/FFmpeg decoder or the Immich playback-stream fallback. AVIF and DNG/ProRAW still need
  libheif/LibRaw builds; HEIC currently depends on the platform decoder.
- The final supported locale list and app branding are not yet decided.

## Change control

- `REQUIREMENTS.md` is the product source of truth; the Phase 0 requirements alignment has been
  applied.
- Architecture changes require an ADR update or a new ADR.
- Plugin API changes require a version bump and a compatibility note.
- Documentation is updated in the same change as requirement-affecting code (NFR-10).
