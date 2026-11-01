# Testing and CI

## 1. Test strategy

| Level | Scope | Tooling |
|---|---|---|
| Unit | Domain, filters, profiles, cache, settings, manifest validation, plugin state/actions | `flutter_test` |
| Widget | Settings groups, install UI, slideshow controls, media grid, dialogs | `flutter_test` |
| Integration | Slideshow, offline cache, plugin install/sandbox, platform channels | `integration_test` |
| Device/manual | Boot/startup, kiosk, sleep inhibit, biometrics, APK install, WebView version | Device or VM |
| Performance | 24/7 stability, memory, FPS, 1 Hz plugins, video | Automated and manual |
| Security | ZIP validation, sandbox, network, storage isolation, secret redaction | Unit/integration/manual |
| Media | Codecs, HDR tone-map, HEIC/AVIF/DNG/ProRAW, Live Photo, fallbacks | Fixtures and reference hardware |

## 2. Unit coverage priorities

- Slideshow sequencing/shuffle and pause/resume.
- Type/aspect filters, unknown dimensions, at-least-one-selection rules.
- Aspect classification boundaries (1.15/1.42/1.64/2.0, orientation-neutral).
- Per-aspect profile resolution, seeding, pan/cover rules.
- Cache resolver: local first, network fallback, offline, checksum mismatch.
- Prefetch/eviction: current/next protected, quota, LRU.
- Settings migrations and persistence.
- Plugin manifest/JSON schema validation, duplicate IDs, API compatibility.
- Plugin snapshot redaction: no API key/server URL/credentials.
- Plugin update-coalescing and rate-limit logic.
- Permissions and `asset.download` degradation.
- Night-mode window boundaries.

## 3. Widget coverage

- Settings groups: expand/collapse, summaries, persistence, tour targets.
- Plugin install: description, screenshots, permissions, compatibility, cancel.
- Plugin details: enable/disable, update, uninstall, placement, settings.
- Media selection: biometric gate, filters, counter.
- Slideshow controls: previous/next, pause, mute, settings, album selection.
- No-items and error states.

## 4. Integration coverage

- Connect to a mock Immich server; permissions; album selection.
- Slideshow photo/video advance; audio; Live Photo modes.
- Offline playback from cache.
- Plugin install/update/disable/uninstall; overlay appears/hides.
- Plugin input: button, external link confirmation, blocked navigation.
- Plugin placement request and persistence.
- Network block/proxy and permission revocation.
- Android WebView baseline/degradation (device/emulator).
- Restart/process-death persistence.

## 5. Media fixtures

Keep fixtures small and legally safe:

- H.264 + AAC MP4.
- HEVC 10-bit HDR10 and HLG clips.
- AV1 clip.
- HEIC 8-bit and 10-bit stills.
- AVIF still.
- DNG and a ProRAW sample.
- Animated GIF.
- Live Photo still + motion MOV pair.
- Missing-dimensions asset.
- Truncated/corrupt files.

Fixtures live outside the main app bundle or in a test-only asset set. Do not commit large media.
The tiny still fixtures in `test/fixtures/stills/` cover the native decode path.

## 6. Performance and security checks

Performance:

- 72-hour slideshow on each platform with video and 3–5 plugin instances at 1 Hz.
- Memory and file-handle growth bounded.
- No player/webview leaks over slide changes and plugin enable/disable cycles.
- 1 Hz plugin updates do not drop slideshow frames.
- 4K video/hardware decode on x64; 1080p on Android reference.
- Cache sync/prefetch under throttled network.
- Disk-full and network-loss recovery.
- Watchdog recovery from a hung plugin/webview/media player.

Security:

- ZIP traversal, zip bombs, oversized files, invalid manifests.
- Duplicate plugin ID and incompatible API version.
- Sandbox escape attempts: host storage, cookies, filesystem, other plugins.
- Direct network blocked; proxy permission/revocation; timeouts.
- External link confirmation and blocked schemes/popups.
- Action rate limits and permission denial.
- Loopback server path traversal/token isolation.
- Secret redaction in logs/crash reports.

## 7. CI

`.github/workflows/ci.yml` runs:

- On every push and pull request: `flutter analyze` and `flutter test` on Ubuntu.
- On non-pull-request runs: debug builds for Android, Windows, and Linux.
- Checkout fetches the two pinned submodules.
- The native still decoders are not built in CI; live native decode tests skip unless the built
  libraries are present.

## 8. Local commands

```bash
flutter pub get
flutter analyze
flutter test
flutter test integration_test -d windows

flutter build windows --release
flutter build linux --release
flutter build apk --release --split-per-abi
```

Native build scripts under `scripts/` handle libheif and LibRaw. Packaging scripts produce Windows
ZIP, Linux tar.gz, and Android split APKs with `sha256sums.txt`. They do not sign or publish
artifacts.
