# Phase 5 — Platform Integration

Status: Not started
Depends on: Phases 1–4
Unblocks: Phase 6

## Goal

Make the app behave as an unattended photo frame on each target: start automatically, stay awake,
run fullscreen, support night mode, protect sensitive navigation, update itself, and expose
diagnostics.

## Scope

### Android

- Boot receiver and start-on-boot setting.
- HOME/launcher role support (user choice; not forced).
- Keep screen on; immersive mode; insets/cutouts; orientation.
- Night mode via window brightness + overlay; slideshow paused.
- Biometric/device credential gate for media navigation and API-key reveal/copy; fail-open
  without a lock.
- Audio focus integration.
- APK update: GitHub check, download, FileProvider, install intent, signature continuity.
- WebView baseline check and plugin degradation.
- App-private cache/settings; secure storage.
- Single-instance behaviour.

### Windows

- Fullscreen/kiosk mode; hide cursor; multi-monitor selection.
- Startup entry/task; launch directly into slideshow.
- Sleep/display inhibition and restoration.
- Single-instance enforcement.
- Update check via GitHub; installer/ZIP flow.
- DPI/scaling behaviour.
- Logs/diagnostics.

### Linux x64

- Fullscreen/kiosk; X11 primary; Wayland validation.
- XDG autostart or systemd user service; autologin/kiosk setup documentation.
- Sleep/DPMS inhibit via logind/DBus.
- Night-mode overlay dimming.
- Single-instance enforcement.
- AppImage/deb packaging; bundled native libraries.
- Update check/release flow.
- Wayland limitations documented.

### Cross-platform

- Settings for automation/startup/kiosk.
- Diagnostics screen: versions, CEF/WebView, cache stats, logs, crash reports, licenses.
- Log rotation/redaction; crash reporting local only.
- Update check UI and release notes.
- Localization completion for the supported locales.
- Onboarding/tour deep links to settings groups.
- Final permission/status messaging.

## Out of scope

- Pi/ARM64, iOS, macOS.
- True HDR output.
- Store distribution.
- Plugin marketplace/signatures.
- Background media playback.

## Tasks

1. Implement platform service interfaces and native channels.
2. Android boot/home/keep-awake/brightness/biometric/installer/WebView checks.
3. Windows startup/kiosk/sleep/single-instance/update.
4. Linux autostart/kiosk/sleep/single-instance/packaging/update.
5. Night-mode integration on all platforms.
6. Diagnostics/logging/about screens.
7. Update-check flows per platform.
8. Localization completion.
9. Packaging scripts and CI artifacts.
10. Manual test checklists per platform.
11. Update docs and platform limitations.

## Deliverables

- Installable artifacts for all three platforms.
- Unattended startup/kiosk/sleep behaviour.
- Biometric gates and update flow.
- Diagnostics and logs.
- Platform test evidence.
- Updated docs.

## Acceptance criteria

- [ ] Android starts the slideshow after reboot (or as HOME) when configured.
- [ ] Android keeps the screen on and applies night-mode brightness.
- [ ] Biometric/device credential gates protect media navigation and key reveal; fail-open without
      a lock.
- [ ] In-app APK update downloads and installs a signed update.
- [ ] Windows starts fullscreen at login and prevents display/system sleep.
- [ ] Linux starts via autostart/systemd and prevents sleep; X11 kiosk works; Wayland status is
      documented.
- [ ] Desktop single-instance works (second launch focuses the existing frame).
- [ ] Night mode works on all platforms (dimming/black overlay; timer paused).
- [ ] Diagnostics screen shows versions, cache stats, logs, and licenses without secrets.
- [ ] Build artifacts are reproducible and documented.
- [ ] CI green; docs updated.

## Risks

| Risk | Mitigation |
|---|---|
| Android background launch restrictions | HOME role + tested boot flow; document device-specific limits |
| Android OEM battery/startup restrictions | Setup guide; test on target devices |
| Linux Wayland/kiosk fragmentation | X11 primary; document compositor setup; validate Wayland |
| Desktop self-update packaging | Check/download/open flow; AppImage replace where possible |
| Secure storage differences | Abstract and test each platform |
| Biometrics on desktop | Windows Hello if available; fail-open with disclosure |
| Start-on-boot permissions | User guidance and diagnostics |

## Delivery log

| Date | Result | Notes |
|---|---|---|
| - | - | - |
