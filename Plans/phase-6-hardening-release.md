# Phase 6 — Hardening and Release

Status: Not started
Depends on: Phases 1–5
Unblocks: v1 release

## Goal

Ship a stable, secure, documented v1 that runs for days unattended on Windows, Linux x64, and
Android, with signed artifacts and known limitations clearly documented.

## Scope

### Stability and performance

- 72-hour soak on each platform with video, photos, cache sync, and 3–5 plugins at 1 Hz.
- Memory/file-handle/player/webview leak checks.
- Frame-drop budget under plugin updates.
- Cache stress: large libraries, disk full, network loss, server down, auth revoked.
- Watchdog/restart behavior for media/plugin hosts.
- Startup performance and slideshow-before-plugins rule.

### Security

- Threat-model review against `Docs/security.md`.
- ZIP fuzzing: traversal, bombs, malformed manifests, oversized images.
- Sandbox/network/storage/link/action tests.
- Secret redaction and log review.
- Loopback server review.
- Update signing/package identity verification.
- Plugin permission/consent UX review.

### Media quality

- Codec/tone-map regression matrix.
- HEIC/AVIF/DNG/ProRAW quality check.
- Live Photo modes/audio.
- Fallback behavior on corrupt files.
- Supported-format documentation.

### Documentation and requirements

- Verify the Phase 0 requirements alignment is applied and update any late deviations (package,
  API 26, no Pi/iOS/macOS, HDR SDR, plugin format, platform mapping).
- Finalize `Docs/` and `Plans/` statuses.
- Plugin authoring guide and API reference.
- Build/run/kiosk/setup guides for Windows, Linux, Android.
- License/third-party notices/source offer.
- Release notes and known limitations.

### Release engineering

- Version `1.0.0`; versionCode/build numbers.
- Android signing keystore in CI; APK per ABI; update test.
- Windows signed artifact (if signing is available) or documented unsigned build.
- Linux AppImage/deb; bundled native libraries.
- Checksums and GitHub release.
- Clean-machine/fresh-install smoke tests.
- Upgrade test for future releases (same app ID/signing key).

### QA matrix

- Windows 10 and 11 x64.
- Ubuntu 22.04/24.04 and Debian 12/13 x64; X11; Wayland status.
- Android API 26 low-end and a modern API 34+ device; arm64 and armeabi-v7a.
- WebView baseline/no-WebView degradation.
- 1080p and 4K where supported.
- Offline/online transitions.
- Boot/kiosk/sleep/biometric/update flows.

## Out of scope

- New features.
- Pi/iOS/macOS.
- True HDR output.
- Plugin marketplace/signatures.
- Multiple plugin instances.

## Tasks

1. Execute soak/perf/security/codec QA.
2. Fix release-blocking defects.
3. Apply requirements/doc updates.
4. Generate license notices/source offer.
5. Finalize build/signing/release workflows.
6. Produce artifacts and checksums.
7. Run clean-install and upgrade smoke tests.
8. Write release notes/known limitations.
9. Tag and publish.
10. Record post-v1 backlog.

## Deliverables

- Signed v1 artifacts for Android, Windows, Linux.
- Release notes, checksums, and known limitations.
- License/third-party notices.
- Complete documentation and phase statuses.
- Test evidence and soak results.

## Acceptance criteria

- [ ] 72-hour soak passes on all platforms without unbounded growth/crashes.
- [ ] Security checklist has no open blockers.
- [ ] Codec/tone-map/RAW/Live Photo matrix passes or documents acceptable fallbacks.
- [ ] Plugin install/sandbox/actions/placement/network/storage tests pass.
- [ ] Android boot/launcher/keep-awake/night/biometric/update flows pass on target devices.
- [ ] Windows/Linux startup/kiosk/sleep/update flows pass.
- [ ] Fresh install and upgrade (same app ID/key) pass.
- [ ] All docs updated; requirements alignment applied.
- [ ] License/notices/source offer packaged.
- [ ] Release artifacts signed and checksums published.
- [ ] Known limitations documented (HDR SDR, WebView baseline, Linux CEF performance, Wayland).

## Risks

| Risk | Mitigation |
|---|---|
| Late CEF/WebView regression | Pin versions; regression tests before release |
| Android OEM startup quirks | Test matrix; setup guide; documented limits |
| Performance on low-end Android | 1080p budget; plugin limits; degrade |
| License/source-offer gaps | Checklist; generated notices; native build pinning |
| Last-minute scope creep | Out-of-scope list; post-v1 backlog |

## Post-v1 backlog

- Pi/ARM64 support.
- iOS (WKWebView, no boot-start, App Store review of downloadable plugins).
- True HDR output via native video surfaces.
- Plugin signatures, remote install/catalog, domain allowlists.
- Multiple plugin instances.
- Additional locales.
- Plugin author tooling/WYSIWYG.
- Remote asset proxying.

## Delivery log

| Date | Result | Notes |
|---|---|---|
| - | - | - |
