# Phase 5 — Platform Integration

Status: In progress (partial platform baseline; Phase 4-dependent items blocked)
Depends on: Phases 1–3 (done; Phase 3 verification gaps remain). Phase 4 is not started; only the
WebView/plugin platform items are blocked on it.
Unblocks: Phase 6

Baseline at revision: `d996627`; `flutter analyze` clean, 269 passed, 2 native skips (without DLLs),
Windows release default and kiosk launches verified and Android split release APKs produced locally,
Linux never runtime verified.
No git remote or release keystore is configured; Android release builds currently use the debug
signing key.

## Goal

Make the app behave as an unattended photo frame on each target: start automatically, stay awake,
run fullscreen, support night mode, protect sensitive navigation, update itself, and expose
diagnostics.

## Starting point (2026-10-31)

### Delivered baseline

- Platform service interfaces exist in `lib/platform/services.dart`: keep-awake, fullscreen,
  biometrics, single-instance, autostart, kiosk, window brightness, and Live Photo capability.
- Fullscreen is wired to settings through `DisplayModeController`: `window_manager` on Windows/Linux
  and immersive-sticky mode on Android.
- Keep-awake is wired through the existing `display.keepScreenOn` setting: `win32`
  `SetThreadExecutionState` on Windows, `systemd-inhibit sleep:idle` with a `wakelock_plus` fallback
  on Linux, and `wakelock_plus` on Android.
- Night mode has scheduled-window logic, overlay dimming, slideshow pause, and overlay hiding;
  covered by unit and widget tests. On Android it sets window brightness to `1 - dimOpacity` and
  restores it when night mode ends or the slideshow closes.
- Media selection and API-key reveal/copy are gated by biometric/device credential when available and
  fail open otherwise.
- Single-instance enforcement uses an exclusive file lock in the support directory and rejects a
  second process. On Windows/Linux, a second launch signals the existing window to show and focus
  over a loopback socket.
- Settings schema is v3. `AutomationSettings` contains `startOnBoot`, `fullscreen`, `kiosk`, and
  `updateChecks`; start-on-boot and kiosk controls exist, but update-check UI/service does not.
- The Automation settings screen exposes start-on-boot, fullscreen, kiosk (desktop only),
  keep-screen-on, night mode, and Android battery-optimization/OEM-autostart/Home-app rows.
- About & diagnostics shows version/build, plugin API v1, platform/OS version, cache statistics,
  recent redacted logs, error count with copy, and opens the Flutter license page.
- Android: manifest declares `RECEIVE_BOOT_COMPLETED`, `WAKE_LOCK`, `USE_BIOMETRIC`,
  `USE_FINGERPRINT`, and `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`; device `dumpsys` shows all granted
  at install. `BootReceiver` syncs start-on-boot to SharedPreferences; HOME intent filter; biometric
  gates for media selection and API-key reveal/copy; Android window brightness. Automation settings
  adds Battery optimization (status + Grant, refreshed on app resume), OEM autostart (Open), and Home
  app (Open); Start on boot is gated on the battery exemption. No runtime permissions are requested.
- Android audio focus: `AudioFocusService` adds `requestAudioFocus`/`abandonAudioFocus` and focus
  change events to the platform channel; `VideoSlide` requests only for unmuted playing media, pauses
  on transient/permanent loss, resumes after transient gain, and reference-counts overlapping slides.
  Unit/widget tested; device verification pending.
- Windows: Run-key autostart
  (`HKCU\Software\Microsoft\Windows\CurrentVersion\Run`, value `PhotoFrame`); kiosk mode (fullscreen,
  always-on-top, skip taskbar, no resize/move/minimize/maximize); cursor hidden via `MouseRegion`;
  system+display keep-awake via `SetThreadExecutionState`; second-instance focus via loopback socket;
  ZIP packaging script. Default and kiosk (`kiosk=true`, `fullscreen=true`) launches are verified:
  `waitUntilReadyToShow()` is awaited after `ensureInitialized()` so `setSkipTaskbar` has a valid
  `ITaskbarList3` pointer; without it, `window_manager_plugin.dll` crashed at 0xC0000005/0xa005.
  Windows fullscreen now uses a visible `WS_POPUP` window without caption/thickframe/system menu,
  sized to the monitor, plus native foreground focus; a manual Win32 check hid the taskbar. App-level
  taskbar/cursor confirmation and sign-in autostart still need a final manual check.
- Linux: XDG autostart `.desktop` entry; kiosk/fullscreen via `window_manager`; `systemd-inhibit`
  `sleep:idle` with `wakelock_plus` fallback; second-instance focus shared with Windows; tar.gz
  packaging script. No Linux host was available; nothing is runtime-verified.
- Packaging scripts: `scripts/package-windows.sh` (ZIP), `scripts/package-linux.sh` (tar.gz), and
  `scripts/package-android.sh` (split release APKs plus `sha256sums.txt`).
- Setup shows Immich permission status and the `asset.download` degradation message.
- The app opens directly at `/slideshow` when a saved connection and album selection exist
  (`Bootstrap.startAtSlideshow`), independent of OS startup.

### Partial baseline

- Android boot is code/prefs verified but not device verified. A real reboot test on a connected
  Xiaomi/MIUI Android 12 device with `start_on_boot=true` did not launch the app. The log reports
  `BroadcastQueueInjector: Unable to launch app com.rincew1nd.photoframe/10006 for broadcast ...
  BOOT_COMPLETED: process is not permitted to auto start`. MIUI autostart permission is required.
  Shell broadcasts are blocked on this non-rooted device. Battery optimization is not exempt on the
  device; start-on-boot is disabled until an exemption is confirmed and is auto-disabled when the
  exemption is absent.
- Android HOME/launcher support is manifest-only plus an Automation row that opens the system Home
  app settings; the user must select the app as home, and on-device verification is pending.
- Android biometric gates and window brightness are implemented but not device-verified.
- Diagnostics still lack WebView/CEF versions; blocked on Phase 4.
- Windows kiosk, Run-key autostart, keep-awake, focus signalling, and ZIP packaging are implemented;
  default and kiosk launches are verified without a crash. Close/alt-tab suppression and multi-monitor
  selection remain missing; visual kiosk behavior and sign-in autostart verification are pending.
- Linux XDG autostart, kiosk/fullscreen, sleep inhibition, focus signalling, and tar.gz packaging are
  implemented. No Linux host was available, so none is runtime-verified; AppImage/deb packaging is
  missing.
- Desktop single-instance prevents duplicates and a second launch signals the existing window to show
  and focus. Verification is pending.
- Update checks, APK download/install, and release notes are missing. There is no GitHub remote/release
  channel and no release keystore; Android release builds use the debug signing key.
- Kiosk mode, always-on-top, and cursor hiding are implemented on Windows/Linux; close/alt-tab
  suppression and multi-monitor selection are still missing.
- Localization is English-only and many screens still use hardcoded strings; the final locale list
  is undecided.
- Permission/status messaging covers Immich permissions plus Android battery-optimization status and
  OEM autostart/Home app shortcuts; install-unknown-apps and richer background-restriction status are
  not reported.
- Audio focus is implemented for unmuted video/Live Photo playback: the Android platform channel requests and abandons focus, and `VideoSlide` pauses on loss and resumes after transient gain. Lease counting prevents overlapping slides from abandoning focus early. Unit/widget tested; device verification pending.

### Blockers and open decisions

- Phase 4 (plugin host) is not started. WebView baseline checks, plugin degradation, CEF diagnostics,
  and plugin hiding during night mode cannot be completed yet.
- The final locale list is undecided, so localization completion cannot be closed.
- There is no GitHub remote/release channel and no release keystore; update checks and signature
  continuity are blocked on those decisions.
- Android OEM autostart policy can block `BOOT_COMPLETED`; MIUI requires the app autostart permission.
  The test device is not exempt from battery optimization, and start-on-boot is gated on that
  exemption.
- Windows installer vs ZIP and Linux AppImage vs deb are not decided. The Windows ZIP and Linux tar.gz
  scripts exist.
- No Linux host is available for runtime validation.

## Scope

Status tags: `[done]`, `[partial]`, `[missing]`, `[blocked]`, `[blocked: Phase 4]`.

### Android

- `[partial]` Boot receiver and start-on-boot setting. Receiver, declared permissions, and
  SharedPreferences sync are implemented. A real reboot on Xiaomi/MIUI Android 12 did not launch the
  app; MIUI autostart permission is required. Battery optimization is not exempt on the device, so
  start-on-boot is disabled until exemption is confirmed and is auto-disabled when it is absent.
  Code/prefs verified.
- `[partial]` HOME/launcher role support. Manifest support and an Automation row that opens the
  system Home app settings are added; user selection is required and on-device verification is
  pending.
- `[partial]` Permission/status reporting. Automation loads battery-optimization status, refreshes it
  on app resume, and offers Grant for the exemption, Open for OEM autostart, and Open for Home app.
  Declared permissions are normal/special and no runtime permissions are requested. Install-unknown-
  apps and richer background-restriction status are not reported.
- `[partial]` Keep screen on; immersive mode; insets/cutouts; orientation. Keep-screen-on and
  immersive mode are wired; orientation locking and cutout handling are not.
- `[partial]` Night mode via window brightness + overlay; slideshow paused. Overlay, pause, hide
  overlays, and window brightness (`1 - dimOpacity`) are implemented and unit/widget tested;
  on-device verification is pending.
- `[partial]` Biometric/device credential gate for media navigation and API-key reveal/copy; fail-open
  without a lock. Media selection and key reveal/copy are gated at code level; device verification
  remains.
- `[partial]` Audio focus. Android requests/releases focus through the platform channel; `VideoSlide`
  pauses on loss and resumes after transient gain, with lease counting for overlapping slides.
  Unit/widget tested; device verification pending.
- `[blocked]` APK update: GitHub check, download, FileProvider, install intent, signature continuity.
  No release channel or release keystore exists; release builds currently use debug signing.
- `[blocked: Phase 4]` WebView baseline check and plugin degradation.
- `[done]` App-private cache/settings; secure storage.
- `[partial]` Single-instance behaviour. The file lock exists; foreground/focus behaviour is unverified.

### Windows

- `[partial]` Fullscreen/kiosk mode; hide cursor; multi-monitor selection. Windows uses a Win32
  `WS_POPUP` fullscreen style with native foreground focus; always-on-top, skip taskbar, no
  resize/move/minimize/maximize, and cursor hiding are implemented; default and kiosk launches are
  verified. A manual Win32 check hid the taskbar; final app-level taskbar/cursor confirmation,
  close/alt-tab suppression, and multi-monitor selection remain.
- `[partial]` Startup entry/task; launch directly into slideshow. Direct-to-slideshow works when a
  session is saved, the HKCU Run-key entry (value `PhotoFrame`) is implemented, and default and kiosk
  launches are verified; sign-in autostart verification is pending.
- `[partial]` Sleep/display inhibition and restoration. `SetThreadExecutionState` requests system and
  display wake; the flags are cleared on disable. Verification is pending.
- `[partial]` Single-instance enforcement. Duplicate processes are rejected and a second launch
  signals the existing window to show/focus over a loopback socket; verification is pending.
- `[blocked]` Update check via GitHub; installer/ZIP flow. ZIP packaging exists; update checks and a
  release channel do not.
- `[partial]` DPI/scaling behaviour. Flutter defaults are used; not verified.
- `[partial]` Logs/diagnostics. Logs and the About screen with cache stats, platform details, and
  licenses exist; CEF/WebView details are blocked.

### Linux x64

- `[partial]` Fullscreen/kiosk; X11 primary; Wayland validation. Fullscreen and kiosk controls are
  wired via `window_manager`; runtime validation is pending and Wayland is unvalidated.
- `[partial]` XDG autostart or systemd user service; autologin/kiosk setup documentation. XDG
  autostart is implemented but unverified; systemd and autologin/kiosk docs are still missing.
- `[partial]` Sleep/DPMS inhibit via logind/DBus. `systemd-inhibit` covers `sleep:idle`; the
  `wakelock_plus` fallback remains for systems without `systemd-inhibit`; runtime verification is
  pending.
- `[partial]` Night-mode overlay dimming. Overlay logic exists; no runtime verification.
- `[partial]` Single-instance enforcement. The file lock and second-launch focus signalling are
  implemented; verification is pending.
- `[partial]` Packaging. `scripts/package-linux.sh` writes a tar.gz; AppImage/deb packaging and
  bundled-native-library validation are missing.
- `[blocked]` Update check/release flow. No release channel or signing exists.
- `[partial]` Wayland limitations documented. Documentation exists; validation is pending.

### Cross-platform

- `[partial]` Settings for automation/startup/kiosk. Fullscreen, keep-awake, night mode,
  start-on-boot, kiosk, and the `updateChecks` field exist; update-check UI/service is absent.
- `[partial]` Diagnostics screen: versions, CEF/WebView, cache stats, logs, error entries, and
  licenses. Version/build, plugin API, platform/OS, cache stats, logs, error entries, and licenses are
  present; CEF/WebView is blocked.
- `[partial]` Log rotation/redaction; crash reporting local only. Rotation and redaction are done;
  crash reports are log entries only.
- `[blocked]` Update check UI and release notes. Blocked on the GitHub release channel and release
  signing.
- `[missing]` Localization completion for the supported locales.
- `[missing]` Onboarding/tour deep links to settings groups.
- `[partial]` Final permission/status messaging. Android battery-optimization status, OEM autostart,
  and Home app shortcuts are present; install-unknown-apps and richer background-restriction status
  are still missing.
- `[partial]` Packaging scripts. Windows ZIP, Linux tar.gz, and Android split APKs with sha256sums
  exist; Windows packaging is Bash/Git Bash, native stills use Windows PowerShell 5.1, and CI release
  artifacts and signing are missing.
- `[partial]` Manual test checklists. `Docs/platform-checklists.md` has Android, Windows, and Linux
  checks; the Android boot failure, Android release install/launch, and Windows default/kiosk launch
  results are recorded, other results are pending.

### Blocked on Phase 4

- WebView baseline and plugin degradation.
- CEF/WebView version reporting in diagnostics.
- Hiding plugins during night mode and while controls/dialogs are open.

## Out of scope

- Pi/ARM64, iOS, macOS.
- True HDR output.
- Store distribution.
- Plugin marketplace/signatures.
- Background media playback.

## Tasks

1. `[done]` Implement platform service interfaces and native channels.
2. `[partial]` Android boot/home/keep-awake/brightness/biometric/installer/WebView checks. Boot
   receiver, declared permissions, battery/OEM/home status rows, HOME manifest support, keep-awake,
  immersive mode, brightness, biometric key protection, and audio focus are implemented. A real MIUI
  reboot did not launch the app and battery optimization is not exempt; boot/home/biometric/audio
  device checks, installer, and WebView remain.
3. `[partial]` Windows startup/kiosk/sleep/single-instance/update/packaging. Win32 popup
   fullscreen/native focus, cursor hiding/always-on-top, the HKCU Run-key entry, system+display
   inhibition, second-launch focus, and the ZIP script are implemented; default and kiosk launches
   are verified after the `waitUntilReadyToShow()` startup fix. A manual Win32 check hid the taskbar.
   Multi-monitor, close/alt-tab suppression, final app-level visual kiosk verification, sign-in
   autostart verification, and updates remain.
4. `[partial]` Linux autostart/kiosk/sleep/single-instance/packaging/update. Kiosk controls, XDG
   autostart, `systemd-inhibit`, the `wakelock_plus` fallback, second-launch focus, and the tar.gz
   script are implemented; no Linux host was available, so runtime verification, AppImage/deb, and
   updates remain.
5. `[partial]` Night-mode integration on all platforms. Overlay, pause, hide-overlays, and Android
   window brightness are done; on-device checks remain.
6. `[partial]` Diagnostics/logging/about screens. Version/build, plugin API, platform/OS, cache stats,
   error entries, logs, and licenses are done; CEF/WebView and a richer crash view remain.
7. `[blocked]` Update-check flows per platform. Blocked on the GitHub release channel and release
   signing.
8. `[missing]` Localization completion. Blocked on the final locale list.
9. `[partial]` Packaging scripts and CI release artifacts. Windows ZIP, Linux tar.gz, and Android split
   APK scripts exist; CI release artifacts and signing are missing.
10. `[partial]` Manual test checklists per platform. `Docs/platform-checklists.md` is added; the Android
    boot failure, Android release install/launch, and Windows default/kiosk launch are recorded, other
    results are pending.
11. `[done]` Update docs and platform limitations. Platform docs, README, security, and checklists are
    aligned to the implemented baseline; pending items are explicit.

## Deliverables

- Installable artifacts for all three platforms.
- Unattended startup/kiosk/sleep behaviour.
- Biometric gates and update flow.
- Diagnostics and logs.
- Platform test evidence.
- Updated docs.

The implemented baseline (automation, diagnostics, and packaging scripts) is delivered. Remaining
runtime verification, release signing/channel, update flow, full kiosk lockdown, Linux validation,
localization, and plugin items remain open. Audio focus is implemented and unit/widget tested;
Android device verification remains.

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

Several criteria have implementation but remain unchecked until runtime evidence is recorded.

Added from the current-state audit:

- [ ] The Android capability channel is either called from Dart or removed; no duplicate native
      paths remain.
- [ ] Wake-lock prevents system sleep on Windows and Linux, verified on hardware.
- [ ] Linux X11 runtime verification is recorded; Wayland limitations are confirmed or updated.
- [ ] A release keystore and GitHub release channel exist; an APK upgrade preserves the signature.
- [ ] All app-owned UI strings are localized according to the final locale decision.
- [ ] Each platform has a manual test checklist with recorded results.

## Risks

| Risk | Mitigation |
|---|---|
| Android background launch restrictions | HOME role + tested boot flow; document device-specific limits |
| Android OEM battery/startup restrictions | Setup guide; battery-optimization exemption and MIUI autostart permission; test on target devices |
| Linux Wayland/kiosk fragmentation | X11 primary; document compositor setup; validate Wayland |
| Desktop self-update packaging | Check/download/open flow; AppImage replace where possible |
| Secure storage differences | Abstract and test each platform |
| Biometrics on desktop | Windows Hello if available; fail-open with disclosure |
| Start-on-boot permissions | User guidance and diagnostics |
| Phase 4 dependency | Ship non-WebView platform work first; keep plugin items blocked |
| Dead platform-channel drift | Remove unused methods or add a single Dart caller; test the channel |
| Linux wake-lock only covers idle | Add and verify system-suspend inhibition |
| Fullscreen is not fully kiosk | Add close/alt-tab suppression and multi-monitor handling or document the limitation |
| Debug-only signing and no release channel | Configure a release keystore and GitHub remote before update work |
| Locale list undecided; hardcoded strings | Decide the list, move strings to ARB, then complete translations |
| No Linux host for validation | Treat Linux runtime as open until a host is available |

## Delivery log

| Date | Result | Notes |
|---|---|---|
| 2026-10-31 | Plan revised | Audited the current app; recorded the delivered platform baseline, partial Android channel, Phase 4 blockers, signing/release-channel gaps, and remaining work. |
| 2026-10-31 | Night brightness and diagnostics | Android window brightness is `1 - dimOpacity` and restores when night mode ends or the slideshow closes. About & diagnostics shows version/build, plugin API, platform/OS, cache stats, redacted logs, error count/copy, and the Flutter license page. |
| 2026-10-31 | Settings schema v3 and Android boot/security | `AutomationSettings` adds `startOnBoot`, `fullscreen`, `kiosk`, and `updateChecks`. Added `BootReceiver` + `RECEIVE_BOOT_COMPLETED`, SharedPreferences sync, HOME intent filter, and biometric gates for media selection and API-key reveal/copy. |
| 2026-10-31 | Desktop automation, focus, and packaging | Windows Run-key autostart, kiosk, system+display keep-awake, loopback focus, and ZIP script; Linux XDG autostart, kiosk, `systemd-inhibit` + fallback, loopback focus, and tar.gz script; Android split APK + sha256 script. Linux runtime is unverified. |
| 2026-10-31 | MIUI boot result | Real reboot with `start_on_boot=true` did not launch on a Xiaomi/MIUI Android 12 device. Log: `BroadcastQueueInjector: Unable to launch app ... BOOT_COMPLETED: process is not permitted to auto start`. MIUI autostart permission is required; code/prefs verified; shell broadcasts are blocked on the non-rooted device. |
| 2026-10-31 | Windows startup crash root cause and fix | `WindowManagerKiosk.enable()` called `setSkipTaskbar(true)`, but the plugin's `taskbar_` `ITaskbarList3` pointer was null because `waitUntilReadyToShow()` had not been called after `ensureInitialized()`. The fault was in `window_manager_plugin.dll` at 0xC0000005/0xa005. `lib/main.dart` now awaits `waitUntilReadyToShow()` on Windows/Linux after initialization. |
| 2026-10-31 | Windows kiosk launch verification | Release build with `kiosk=true`/`fullscreen=true` stayed alive 10s; `kiosk=false` stayed alive 5s; no new Application Error events; settings restored. The Windows ZIP was rebuilt: `dist/photo-frame-windows-x64.zip`, 36,761,409 bytes. Full suite 261 passed, 2 skipped; `flutter analyze` clean. Visual kiosk behavior remains unverified. |
| 2026-10-31 | Packaging and native-script compatibility | Windows packaging is `scripts/package-windows.sh` (Bash; run with Git Bash) and uses `powershell.exe` for ZIP creation. `scripts/fetch-stills-deps.ps1` now requires Windows PowerShell 5.1, not 7, and parsed successfully under 5.1. Stale PowerShell wrapper references were removed; the full native still build was not run. |
| 2026-10-31 | Android permissions and automation checks | Manifest declares `WAKE_LOCK`, `USE_BIOMETRIC`, `USE_FINGERPRINT`, `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`, and `RECEIVE_BOOT_COMPLETED`; device `dumpsys` shows all granted at install, and no runtime permissions are requested. Automation loads battery-optimization status, refreshes on app resume, and adds Battery optimization/Grant, OEM autostart/Open, and Home app/Open rows; Start on boot is gated on the exemption and auto-disabled when absent. Device is not exempt; MIUI autostart is still required. Android debug APK builds and MainActivity resumes. |
| 2026-10-31 | Android release reinstall | `dist/photo-frame-android/app-arm64-v8a-release.apk` (35,950,837 bytes, SHA-256 `ABB3A20EFD63127CC98C73A9860ABCBA48395534AF6D090E3C4C4D37DC7DA3E0`) installed and launched successfully; all five declared permissions remained granted. |
| 2026-10-31 | Android audio focus | Added `AudioFocusService` and Android `requestAudioFocus`/`abandonAudioFocus` with focus-loss events. `VideoSlide` requests focus only for unmuted playback, pauses on loss, resumes after transient gain, and reference-counts overlapping slides so AnimatedSwitcher disposal cannot abandon the next slide's focus. Unit/widget tested; device verification pending. |
| 2026-10-31 | Windows fullscreen and slideshow presentation | Windows now uses a Win32 `WS_POPUP` fullscreen style with caption/thickframe/system-menu removal, monitor-sized bounds, native foreground focus, and topmost kiosk handling; `WindowManagerFullscreen` still uses `window_manager` on Linux. Live Photo and video branches now receive the adaptive blurred background, removing the black sidebars seen with `fit: contain`. Full suite 269 passed, 2 skipped; `flutter analyze` clean. A manual Win32 check hid the taskbar; final app-level taskbar/cursor confirmation remains pending. |
