# Platform Support

Status: Draft v0.1
Related: [`architecture.md`](architecture.md), [`security.md`](security.md),
[`testing-ci.md`](testing-ci.md)

## 1. Support matrix

| Platform | Version | Architecture | Status |
|---|---|---|---|
| Windows | 10, 11 | x64 | Supported |
| Linux | Ubuntu 22.04/24.04, Debian 12/13 | x64 | Supported; X11 primary, Wayland validated |
| Android | 8.0+ (API 26) | arm64-v8a, armeabi-v7a | Supported; split APKs |
| iOS, macOS, Pi/ARM64 | - | - | Out of scope v1 |

The application is a single Flutter codebase. Platform-specific code is limited to OS integration
and native libraries.

## 2. Common behaviour

- Full-screen slideshow; controls appear temporarily; dialogs are app-rendered.
- Single-instance enforcement.
- Keep-awake while the frame is running (configurable).
- Night mode: dim/black overlay and paused slideshow; plugins hidden by default.
- Start-on-boot or auto-start as configured.
- Settings, plugin state, and cache persist across normal process death.
- Logs and crash reports are local and redacted.
- No background media playback.

## 3. Android

### Build and distribution

- minSdk 26 (Android 8.0); target latest stable SDK.
- ABIs: arm64-v8a and armeabi-v7a; split APKs to control size.
- New application ID `com.rincew1nd.photoframe`; new signing key.
- Sideload via GitHub releases; in-app update downloads the APK and launches the system installer.
- `REQUEST_INSTALL_PACKAGES` and a FileProvider are required for APK installation.
- No Play Store dependency or policy constraints.

### WebView and plugins

- Plugins use the system WebView (`webview_flutter`).
- Minimum plugin baseline: Chrome/WebView 100+ (proposed; validate in Phase 0).
- Runtime check:
  - below baseline: plugins disabled with an explanatory message;
  - modern WebView: plugins enabled.
- Built-in clock/weather/metadata overlays remain Flutter widgets and do not depend on WebView.
- Android 8 devices with Google Play can update WebView; devices without GMS may have a frozen
  WebView. Plugins degrade; the slideshow does not.
- WebView transparency and platform-view z-order are validated in Phase 0. Fallback: hide plugin
  webviews while app controls/dialogs are open.

### Start on boot and launcher

- Boot receiver (`BOOT_COMPLETED`) starts the slideshow.
- Launcher/home replacement uses a HOME intent filter; the user chooses the app as home.
- Background activity launch restrictions apply on newer Android versions. The existing app’s
  guard/approach is a reference; Phase 5 validates on API 26 through current.
- Boot-start and launcher mode are independent settings.

### Display

- Keep screen on: `FLAG_KEEP_SCREEN_ON` / wakelock.
- Night mode: window brightness; black overlay; timer paused.
- Immersive mode; respect display cutouts and system insets.
- Orientation follows the device or is locked by the user.

### Security

- Biometric/device credential gate for media/library navigation and API-key reveal/copy, where a
  screen lock exists.
- Fail-open for navigation on devices without a lock, per BR-07.
- API key/OAuth tokens in Android Keystore-backed secure storage.
- App-private cache; no broad storage permission.
- APK updates verify the package signature through the Android installer.

### Audio

- Audio focus requested when video/Live Photo audio plays.
- Mute state is global; audio does not continue in the background.

### Packaging

- Release APK per ABI plus a universal debug/QA build if needed.
- Version code increments for every release.
- Update channel: GitHub releases for this application ID.

## 4. Windows

### Build and distribution

- Windows 10/11 x64.
- Flutter Windows desktop build; CEF, libmpv, libheif, and LibRaw bundled.
- Artifact: installer or ZIP; final format decided in Phase 5.
- Signed binary recommended; not required for sideload.
- In-app update check against GitHub releases; desktop may open the release/download page rather
  than self-replacing.

### Display and kiosk

- Fullscreen/kiosk mode; hide cursor; prevent display/system sleep.
- Multi-monitor: use the configured display; default to primary.
- DPI scaling respected; no fractional-scaling hacks.

### Start on boot

- Startup entry (Run key or Startup folder) or scheduled task.
- Auto-start can launch directly into fullscreen slideshow.
- Single-instance enforcement: a second launch focuses the existing window.

### Sleep prevention

- `SetThreadExecutionState` (display/system required) while the frame is active.
- Restore the previous state on exit.

### Native libraries

- CEF (webview_cef) with its helper processes.
- libmpv/FFmpeg from the media_kit package or a pinned build.
- libheif and LibRaw built for x64 and bundled as DLLs.
- Third-party notices included.

## 5. Linux x64

### Supported distributions

- Ubuntu 22.04/24.04 x64.
- Debian 12/13 x64.
- Other distributions are best-effort; document required GTK/CEF/GL libraries.

### Display protocol

- **X11 primary**: predictable kiosk, autostart, DPMS/screen-saving inhibit, and fullscreen.
- **Wayland validated during Phase 0/5**: Flutter runs through GTK; CEF offscreen rendering is
  independent of the compositor; kiosk/sleep inhibit still need compositor-specific testing.
- Do not claim Wayland support until the validation is complete.

### Kiosk and startup

- XDG autostart or a systemd user service, with desktop login/autologin.
- Fullscreen; hide cursor; single instance.
- True boot-to-frame requires autologin plus a kiosk session; document the OS setup, not just the
  app.
- Keep-awake via logind/DBus or equivalent; display DPMS disabled while active.
- Brightness is not standardised: use a black overlay for night mode; do not promise panel
  brightness control.

### Media

- libmpv with system or bundled FFmpeg; hardware decode via VA-API/NVDEC where available.
- media_kit Linux requires libmpv; bundle it for AppImage consistency.
- CEF on Linux uses software OSR readback; keep plugin webviews small and low-frequency.

### Packaging

- AppImage and/or .deb; final choice in Phase 5.
- Bundle native libraries; document any system dependencies.
- Self-update is packaging-dependent; the app may check GitHub and direct the user to the artifact.

## 6. Desktop equivalents for Android-only requirements

| Android feature | Windows | Linux |
|---|---|---|
| Start on boot | Startup entry/task | XDG autostart/systemd user service |
| Launcher/home replacement | Kiosk/fullscreen mode; no launcher replacement | Kiosk/fullscreen session; no launcher replacement |
| Keep screen on | Execution-state inhibit | logind/DBus inhibit; DPMS off |
| Night-mode brightness | Overlay dimming | Overlay dimming |
| Biometric gate | Windows Hello if available; otherwise fail-open | No standard biometric; fail-open |
| Cutouts/insets | OS-reported safe area (usually zero) | OS-reported safe area (usually zero) |
| APK update | Installer/ZIP download + replace flow | AppImage/deb update flow or release page |
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
| HDR | All platforms output SDR; HDR originals are tone-mapped |
| Linux CEF | Software OSR; may limit full-screen plugin performance |
| Android WebView | Depends on system WebView; old devices lose plugins |
| Linux Wayland | Validated later; X11 is the v1 kiosk path |
| Linux brightness | No universal panel-brightness API |
| Windows/Linux biometrics | Windows Hello if present; Linux fail-open |
| Desktop launcher | No OS home/launcher replacement equivalent |
| True boot-to-app | Requires OS autologin/kiosk configuration |
| APK updates | Sideload; user must allow installs from the app |
