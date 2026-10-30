# Testing, CI, Build, and Release

Status: Draft v0.1
Related: [`architecture.md`](architecture.md), [`media.md`](media.md), [`plugins.md`](plugins.md),
[`security.md`](security.md)

## 1. Test strategy

| Level | Scope | Tooling |
|---|---|---|
| Unit | Domain, filters, profiles, cache, settings, manifest validation, plugin state/actions | `flutter_test` |
| Widget | Settings groups, install UI, slideshow controls, media grid, dialogs | `flutter_test` |
| Integration | Slideshow, offline cache, plugin install/sandbox, platform channels | `integration_test` |
| Platform/manual | Boot/startup, kiosk, sleep inhibit, biometrics, APK install, WebView version | Device/VM checklists |
| Performance/soak | 24/7 stability, memory, FPS, 1 Hz plugins, video | Automated + manual |
| Security | ZIP validation, sandbox, network, storage isolation, secret redaction | Unit/integration/manual |
| Media | Codecs, HDR tone-map, HEIC/AVIF/DNG/ProRAW, Live Photo, fallbacks | Fixtures + reference hardware |

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
- No-items state and error states.

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

## 6. Reference environments

| Platform | Reference |
|---|---|
| Windows | Windows 10/11 x64, integrated GPU |
| Linux | Ubuntu 24.04 x64, Intel/AMD GPU, X11 and Wayland |
| Android | API 26 low-end tablet and a modern API 34+ device, arm64 and armeabi-v7a |

Record WebView/CEF versions, GPU, and driver in performance results.

## 7. Performance and soak tests

- 72-hour slideshow on each platform with video and 3–5 plugin instances at 1 Hz.
- Memory and file-handle growth bounded.
- No player/webview leaks over slide changes and plugin enable/disable cycles.
- 1 Hz plugin updates do not drop slideshow frames.
- 4K video/hardware decode on x64; 1080p on Android reference.
- Cache sync/prefetch under throttled network.
- Disk-full and network-loss recovery.
- Watchdog recovery from hung plugin/webview/media player.

## 8. Security tests

- ZIP traversal, zip bombs, oversized files, invalid manifests.
- Duplicate plugin ID and incompatible API version.
- Sandbox escape attempts: host storage, cookies, filesystem, other plugins.
- Direct network blocked; proxy permission/revocation; timeouts.
- External link confirmation and blocked schemes/popups.
- Action rate limits and permission denial.
- Loopback server path traversal/token isolation.
- Secret redaction in logs/crash reports.
- APK signature verification/update path.

## 9. CI

GitHub Actions matrix:

| Job | Runner | Outputs |
|---|---|---|
| Analyze/test | Ubuntu | `flutter analyze`, unit/widget tests |
| Android | Ubuntu | Split APKs; integration tests on emulator where practical |
| Windows | Windows | Release build; CEF/native libraries; installer/ZIP |
| Linux | Ubuntu | Release build; AppImage/deb |
| Native libs | Ubuntu/Windows | Pinned libheif/LibRaw builds; CEF cache |
| Release | Ubuntu | Signed artifacts, checksums, notices |

CI requirements:

- Pin Flutter and dependencies.
- Cache Flutter, CEF downloads, and native build artifacts.
- Build native libraries for x64 and both Android ABIs.
- Run tests before packaging.
- Verify license/notice generation.
- Sign Android release APKs with the new keystore stored in CI secrets.
- Publish checksums and release notes.
- Do not run long soak tests in normal PR CI; schedule them.

## 10. Build commands (target shape)

```bash
flutter pub get
flutter analyze
flutter test
flutter test integration_test -d windows
flutter build windows --release
flutter build linux --release
flutter build apk --release --split-per-abi
```

Native build scripts under `scripts/` handle libheif, LibRaw, CEF, and packaging. Exact commands are
documented when the scaffold is created.

## 11. Release checklist

- [ ] App version and plugin API version bumped.
- [ ] Requirements/docs updated.
- [ ] Unit/widget/integration tests pass.
- [ ] Soak/performance results recorded.
- [ ] Security checklist complete.
- [ ] License/notices/source offer packaged.
- [ ] Windows/Linux artifacts built and smoke-tested.
- [ ] Android APKs signed, installed over the previous build, and updated in-app.
- [ ] Fresh-install setup verified (no migration expected).
- [ ] Plugin reference bundle install/disable/uninstall verified.
- [ ] Offline/start-on-boot/kiosk/sleep checks verified.
- [ ] Checksums and release notes published.
- [ ] Known limitations documented (HDR SDR, WebView baseline, Linux CEF performance).

## 12. Definition of done

A phase is done when:

- its acceptance criteria are met on all supported platforms;
- tests are added/updated;
- documentation is updated;
- no known regression in earlier phases;
- performance and security budgets are still met;
- the change is included in the release notes.
