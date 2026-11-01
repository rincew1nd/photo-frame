# Platform Support

Status: Draft v0.2
Last updated: 2026-10-31
Related: [`architecture.md`](architecture.md), [`security.md`](security.md),
[`testing-ci.md`](testing-ci.md), [`platform-checklists.md`](platform-checklists.md)

## 1. Support matrix

| Platform | Version | Architecture | Status |
|---|---|---|---|
| Windows | 10, 11 | x64 | Supported; Win32 popup fullscreen/kiosk and ZIP packaging implemented; default and kiosk launches verified, final taskbar/cursor and sign-in autostart checks pending |
| Linux | Ubuntu 22.04/24.04, Debian 12/13 | x64 | Supported build target; no Linux runtime validation recorded |
| Android | 8.0+ (API 26) | arm64-v8a, armeabi-v7a | Supported; split APKs; permissions and battery/OEM checks added; boot test failed on MIUI |
| iOS, macOS, Pi/ARM64 | - | - | Out of scope v1 |

The application is a single Flutter codebase. Platform-specific code is limited to OS integration
and native libraries.

## 2. Common behaviour

Implemented:

- Full-screen slideshow; controls appear temporarily; dialogs are app-rendered.
- Single-instance enforcement. On Windows/Linux a second launch signals the existing window to show
  and focus; runtime verification is pending.
- Configurable keep-awake: system and display on Windows, `sleep:idle` inhibit on Linux, and a
  wakelock on Android.
- Night mode: dim/black overlay, paused slideshow, hidden overlays. Android also sets window
  brightness to `1 - dimOpacity` and restores it when night mode ends or the slideshow closes.
- Start-on-boot settings on Windows, Linux, and Android. Android start-on-boot is gated on a
  battery-optimization exemption.
- Settings schema v3 persists automation, display, cache, and connection state.
- Logs rotate and redact secrets. About & diagnostics shows version/build, plugin API v1,
  platform/OS version, cache statistics, recent logs, error count/copy, and the Flutter license page.
- No background media playback.

Pending:

- Update checks, download, and install.
- Full kiosk lockdown (close/alt-tab suppression and multi-monitor selection).
- Localization completion.
- Plugin host, WebView checks, and CEF diagnostics (Phase 4).

## 3. Android

### Build and distribution

- minSdk 26 (Android 8.0); target latest stable SDK.
- ABIs: arm64-v8a and armeabi-v7a; split release APKs to control size.
- Application ID `com.rincew1nd.photoframe`.
- `scripts/package-android.sh` builds split release APKs and writes `sha256sums.txt`.
- Release builds currently use the debug signing key; no release keystore is configured.
- Sideload only. In-app APK download/install is not implemented and is blocked on a release channel
  and release signing. `REQUEST_INSTALL_PACKAGES` and a FileProvider are not present yet.
- No Play Store dependency or policy constraints.

### WebView and plugins

- Phase 4 is not started; no WebView baseline check or plugin degradation is implemented or verified.
- Planned: plugins use the system WebView (`webview_flutter`), with a proposed Chrome/WebView 100+
  baseline to validate in Phase 4.
- Planned: clock/weather/metadata ship as bundled plugins, so all overlays depend on WebView.
- Planned fallback: below baseline, plugins (and therefore all overlays) are disabled with an
  explanatory message; the slideshow continues without overlays.

### Start on boot and launcher

- `BootReceiver` is registered for `BOOT_COMPLETED`, gated by the `start_on_boot` SharedPreferences
  value written by the app.
- The manifest declares `RECEIVE_BOOT_COMPLETED`, `WAKE_LOCK`, `USE_BIOMETRIC`, `USE_FINGERPRINT`,
  and `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`. Device `dumpsys` shows all granted at install; no
  runtime permissions are requested.
- Automation loads battery-optimization status, refreshes it on app resume, and shows a **Battery
  optimization** row with **Grant**. Start on boot is disabled until the exemption is confirmed and
  is auto-disabled when the exemption is absent. The test device is **not exempt**.
- An **OEM autostart** row opens the manufacturer's autostart settings. A **Home app** row opens the
  system Home app settings.
- The HOME intent filter lets the user choose the app as home. It is not an app setting and is not
  yet device-verified.
- A real reboot test on a connected Xiaomi/MIUI Android 12 device with `start_on_boot=true` did not
  launch the app. The log reports
  `BroadcastQueueInjector: Unable to launch app com.rincew1nd.photoframe/10006 for broadcast ...
  BOOT_COMPLETED: process is not permitted to auto start`. MIUI autostart permission is required.
  Shell broadcasts are blocked on this non-rooted device.
- Code and preferences are verified; real boot launch is not. Battery exemption and OEM autostart
  remain prerequisites.
- Background activity launch restrictions still apply on newer Android versions; validate on API 26
  through current.

### Display

- Keep screen on via the existing wakelock path; immersive-sticky mode for fullscreen.
- Night mode: window brightness `1 - dimOpacity`, black overlay, paused slideshow, hidden overlays;
  brightness restores when night mode ends or the slideshow closes. Unit/widget tested; on-device
  verification pending.
- Orientation locking and display-cutout/inset handling are not implemented.

### Security

- Biometric/device credential gate for media selection and API-key reveal/copy where a screen lock
  exists. Fail-open without a lock, per BR-07. Device verification pending.
- Declared permissions are `RECEIVE_BOOT_COMPLETED`, `WAKE_LOCK`, `USE_BIOMETRIC`, `USE_FINGERPRINT`,
  and `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`; all are granted at install and no runtime permissions
  are requested. Battery-optimization exemption is a user-granted special access and is not granted
  on the test device.
- API key/OAuth tokens in Android Keystore-backed secure storage.
- App-private cache; no broad storage permission.
- APK updates are not implemented. Release builds are debug-signed; the system installer will verify
  signature and package identity once an update path exists.

### Audio

- Audio focus is requested through the platform channel only while unmuted video/Live Photo playback
  is active. `VideoSlide` pauses on transient or permanent loss and resumes after a transient gain;
  reference-counted leases keep overlapping slides from abandoning focus early. Unit/widget tested;
  on-device verification is pending.
- Mute state is global; background media playback is not supported.

### Packaging

- Split release APKs per ABI plus `sha256sums.txt` via `scripts/package-android.sh`.
- Version code increments for every release.
- Update channel: pending. No GitHub releases or release keystore are configured.

## 4. Windows

### Build and distribution

- Windows 10/11 x64.
- Flutter Windows desktop build.
- `scripts/package-windows.sh` builds the release bundle and writes
  `dist/photo-frame-windows-x64.zip`.
- Windows packaging scripts are Bash; run them with Git Bash. `scripts/fetch-stills-deps.ps1`
  requires Windows PowerShell 5.1, not PowerShell 7.
- The release ZIP was rebuilt after the startup fix: `dist/photo-frame-windows-x64.zip`, 36,761,409
  bytes. Default and kiosk launches are verified.
- Installer vs ZIP is not decided. No signed binary or release channel is configured.
- In-app update checks are not implemented.

### Display and kiosk

- Kiosk mode: Win32 `WS_POPUP` fullscreen with caption/thickframe/system-menu removed, monitor-sized
  bounds, native foreground focus, always-on-top, skip taskbar, and no resize/move/minimize/maximize;
  cursor hidden via `MouseRegion`. Linux still uses `window_manager`.
- `setSkipTaskbar` requires the plugin's `ITaskbarList3` pointer, which is initialized by
  `waitUntilReadyToShow()`. `lib/main.dart` now awaits it after `ensureInitialized()` on Windows/Linux;
  before the fix, `setSkipTaskbar(true)` crashed in `window_manager_plugin.dll` (0xC0000005/0xa005).
- Default and kiosk (`kiosk=true`, `fullscreen=true`) launches are verified: the process stayed alive
  10s; `kiosk=false` stayed alive 5s; no new Application Error events; settings restored. A manual
  Win32 check using the same popup style and foreground focus hid the taskbar.
- Final app-level visual kiosk/taskbar/cursor confirmation is pending.
- Missing: close/alt-tab suppression and multi-monitor selection.
- DPI scaling uses Flutter defaults; not verified.

### Start on boot

- HKCU Run-key autostart under `Software\Microsoft\Windows\CurrentVersion\Run`, value `PhotoFrame`.
- Default and kiosk launches are verified; sign-in autostart remains pending manual verification.
- Auto-start can launch directly into the slideshow when a session is saved.
- Single-instance enforcement uses a file lock; a second launch signals the existing window to show
  and focus over a loopback socket. Runtime verification pending.

### Sleep prevention

- `SetThreadExecutionState` requests `ES_SYSTEM_REQUIRED` and `ES_DISPLAY_REQUIRED` with
  `ES_CONTINUOUS` while the frame is active.
- The flags are cleared when keep-awake is disabled. Runtime verification pending.

### Native libraries

- CEF for plugins remains Phase 4 work.
- libmpv/FFmpeg and the still decoders (libheif/LibRaw) are required for media playback. Windows
  native still decoding was verified locally; Linux and Android native builds remain unverified.
- Third-party notices are required in packaged artifacts.

## 5. Linux x64

### Supported distributions

- Ubuntu 22.04/24.04 x64.
- Debian 12/13 x64.
- Other distributions are best-effort; document required GTK/GL libraries.
- No Linux host was available, so no Linux runtime result is recorded.

### Display protocol

- **X11 primary**: intended path for kiosk, autostart, and sleep inhibit.
- **Wayland is not validated.** Flutter runs through GTK; compositor-specific kiosk and sleep-inhibit
  behavior must be tested before claiming Wayland support.

### Kiosk and startup

- XDG autostart `.desktop` entry is implemented. A systemd user service and autologin/kiosk setup
  documentation are still missing.
- Fullscreen/kiosk controls are wired via `window_manager`; runtime validation pending.
- Single-instance uses the shared file lock and loopback focus signalling; runtime validation
  pending.
- Keep-awake uses `systemd-inhibit --what=sleep:idle` with a `wakelock_plus` fallback. The fallback
  covers idle only. Runtime validation pending.
- Brightness is not standardised: night mode uses a black overlay; no panel-brightness control.

### Media

- libmpv/FFmpeg are required; hardware decode via VA-API/NVDEC where available.
- Linux native library builds and runtime playback are unverified.
- CEF on Linux remains Phase 4 work.

### Packaging

- `scripts/package-linux.sh` builds the release bundle and writes
  `dist/photo-frame-linux-x64.tar.gz`.
- AppImage and .deb packaging are not implemented.
- Self-update is not implemented; a future flow may check GitHub and direct the user to an artifact.
- Native libraries and system dependencies still need validation on a Linux host.

## 6. Desktop equivalents for Android-only requirements

| Android feature | Windows | Linux |
|---|---|---|
| Start on boot | HKCU Run-key entry; default/kiosk launches verified, sign-in pending | XDG autostart; implemented, runtime pending |
| Launcher/home replacement | Kiosk/fullscreen only; no launcher replacement | Kiosk/fullscreen only; no launcher replacement |
| Keep screen on | `SetThreadExecutionState` system+display; runtime pending | `systemd-inhibit sleep:idle` + fallback; runtime pending |
| Night-mode brightness | Overlay dimming only | Overlay dimming only |
| Biometric gate | Windows Hello if available; otherwise fail-open; unverified | No standard biometric; fail-open; unverified |
| Cutouts/insets | OS-reported safe area; pending validation | OS-reported safe area; pending validation |
| APK update | Not implemented; blocked on release channel | Not implemented; blocked on release channel |
| OLED burn-in motion | Ken Burns/pan applies | Ken Burns/pan applies |

## 7. iOS, macOS, Pi, and ARM64

Out of scope for v1. The domain/UI layers avoid desktop-only assumptions, but no platform work,
builds, testing, or store compliance is planned.

A future iOS version would require:

- WKWebView plugin host;
- no start-on-boot/launcher mode;
- App Store review of downloadable plugin code;
- different secure storage and update models.

A future Pi/ARM64 version would require:

- ARM64 CEF and native library builds;
- hardware decode validation;
- reduced plugin budgets;
- Pi-specific kiosk/packaging.

## 8. Known platform limitations

| Area | Limitation |
|---|---|
| HDR | All platforms output SDR; HDR tone-mapping remains unverified |
| Android boot | Boot start requires OEM autostart permission; the app also gates start-on-boot on a battery-optimization exemption. A Xiaomi/MIUI Android 12 reboot test failed with `process is not permitted to auto start`; the test device is not exempt, and shell broadcasts are blocked on the non-rooted device |
| Android battery optimization | Start-on-boot is disabled until the exemption is confirmed and auto-disabled when absent; the test device is not exempt |
| Android OEM autostart | MIUI and some other OEMs require a separate autostart permission; `BOOT_COMPLETED` does not launch the app without it |
| Android signing | Release builds use the debug signing key; no release keystore |
| Updates | Update-check UI, APK download/install, and desktop update flow are not implemented; no GitHub release channel |
| Full kiosk | Close/alt-tab suppression and multi-monitor selection are missing on Windows/Linux |
| Linux runtime | No Linux host was available; X11, Wayland, kiosk, sleep inhibit, and packaging are unverified |
| Linux packaging | tar.gz script exists; AppImage and .deb are not implemented |
| Linux CEF | Phase 4 not started; no CEF/webview runtime validation |
| Android WebView | Phase 4 not started; system WebView baseline/degradation not validated |
| Linux Wayland | Unvalidated; X11 is the intended v1 kiosk path |
| Linux brightness | No universal panel-brightness API; night mode uses an overlay |
| Windows/Linux biometrics | Windows Hello if present; Linux fail-open; desktop paths unverified |
| Desktop launcher | No OS home/launcher replacement equivalent |
| True boot-to-app | Requires OS autologin/kiosk configuration |
| Localization | English-only; final locale list undecided |
| Audio focus | Implemented and unit/widget tested; Android device verification pending |
