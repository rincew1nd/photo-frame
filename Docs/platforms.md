# Platform Support

## 1. Support matrix

| Platform | Version | Architecture | Support |
|---|---|---|---|
| Windows | 10, 11 | x64 | Supported |
| Linux | Ubuntu 22.04/24.04, Debian 12/13 | x64 | Supported build target; runtime not validated |
| Android | 8.0+ (API 26) | arm64-v8a, armeabi-v7a | Supported; sideloaded APKs |
| iOS, macOS, Pi/ARM64 | - | - | Out of scope for v1 |

The application is a single Flutter codebase. Platform-specific code is limited to OS integration
and native libraries.

## 2. Common behaviour

- Full-screen slideshow; controls appear temporarily; dialogs are app-rendered.
- Single-instance enforcement. On Windows and Linux, a second launch signals the existing window to
  show and focus.
- Configurable keep-awake: system and display on Windows, `sleep:idle` inhibit on Linux, and a
  wakelock on Android.
- Night mode: dim/black overlay, paused slideshow, hidden overlays. Android also sets window
  brightness to `1 - dimOpacity` and restores it when night mode ends or the slideshow closes.
- Start-on-boot on Windows, Linux, and Android. Android start-on-boot is gated on a
  battery-optimization exemption.
- Settings persist automation, display, cache, and connection state.
- Logs rotate and redact secrets. About & diagnostics shows version/build, plugin API v1,
  platform/OS version, cache statistics, recent logs, error count/copy, and the Flutter license page.
- No background media playback.
- Plugin overlays use CEF on desktop and the system WebView on Android.

Not implemented:

- Update checks, download, and install.
- Full kiosk lockdown (close/alt-tab suppression and multi-monitor selection).
- Localization beyond English.

## 3. Android

### Build and distribution

- minSdk 26 (Android 8.0); target latest stable SDK.
- ABIs: arm64-v8a and armeabi-v7a; split release APKs control size.
- Application ID `com.rincew1nd.photoframe`.
- `scripts/package-android.sh` builds split release APKs and writes `sha256sums.txt`.
- Sideload only. No Play Store dependency or policy constraints.
- `REQUEST_INSTALL_PACKAGES` and a FileProvider are not present.

### WebView and plugins

- Plugins use the system WebView (`webview_flutter`).
- Plugins require Chromium 100+. Below that baseline, plugins (and therefore all overlays) are
  disabled with an explanatory message; the slideshow continues without overlays.
- Clock, weather, and metadata ship as bundled example plugins, so all overlays depend on the
  WebView.

### Start on boot and launcher

- `BootReceiver` is registered for `BOOT_COMPLETED`, gated by the `start_on_boot` SharedPreferences
  value written by the app.
- The manifest declares `RECEIVE_BOOT_COMPLETED`, `WAKE_LOCK`, `USE_BIOMETRIC`, `USE_FINGERPRINT`,
  and `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`; no runtime permissions are requested.
- Automation loads battery-optimization status, refreshes it on app resume, and shows a **Battery
  optimization** row with **Grant**. Start on boot is disabled until the exemption is confirmed and
  is auto-disabled when the exemption is absent.
- An **OEM autostart** row opens the manufacturer's autostart settings. A **Home app** row opens the
  system Home app settings.
- The HOME intent filter lets the user choose the app as home.
- MIUI and some other OEM builds block `BOOT_COMPLETED` until their autostart permission is granted.

### Display

- Keep screen on via the wakelock path; immersive-sticky mode for fullscreen.
- Night mode: window brightness `1 - dimOpacity`, black overlay, paused slideshow, hidden overlays;
  brightness restores when night mode ends or the slideshow closes.
- Orientation locking and display-cutout/inset handling are not implemented.

### Security

- Biometric/device credential gate for media selection and API-key reveal/copy where a screen lock
  exists. Fails open without a lock.
- API key and OAuth tokens use Android Keystore-backed secure storage.
- App-private cache; no broad storage permission.

### Audio

- Audio focus is requested through the platform channel only while unmuted video/Live Photo playback
  is active. `VideoSlide` pauses on transient or permanent loss and resumes after a transient gain;
  reference-counted leases keep overlapping slides from abandoning focus early.
- Mute state is global; background media playback is not supported.

### Packaging

- Split release APKs per ABI plus `sha256sums.txt` via `scripts/package-android.sh`.
- Version code increments for every release.
- No in-app update channel.

## 4. Windows

### Build and distribution

- Windows 10/11 x64.
- Flutter Windows desktop build.
- `scripts/package-windows.sh` builds the release bundle and writes
  `dist/photo-frame-windows-x64.zip`.
- Windows packaging scripts are Bash; run them with Git Bash. `scripts/fetch-stills-deps.ps1`
  requires Windows PowerShell 5.1, not PowerShell 7.
- Installer versus ZIP distribution is not decided.

### Display and kiosk

- Kiosk mode: Win32 `WS_POPUP` fullscreen with caption/thickframe/system-menu removed, monitor-sized
  bounds, native foreground focus, always-on-top, skip taskbar, and no
  resize/move/minimize/maximize; cursor hidden via `MouseRegion`.
- `setSkipTaskbar` requires the plugin's `ITaskbarList3` pointer, initialized by
  `waitUntilReadyToShow()`.
- Missing: close/alt-tab suppression and multi-monitor selection.
- DPI scaling uses Flutter defaults.

### Start on boot

- HKCU Run-key autostart under `Software\Microsoft\Windows\CurrentVersion\Run`, value `PhotoFrame`.
- Auto-start can launch directly into the slideshow when a session is saved.
- Single-instance enforcement uses a file lock; a second launch signals the existing window to show
  and focus over a loopback socket.

### Sleep prevention

- `SetThreadExecutionState` requests `ES_SYSTEM_REQUIRED` and `ES_DISPLAY_REQUIRED` with
  `ES_CONTINUOUS` while the frame is active.
- The flags are cleared when keep-awake is disabled.

### Native libraries

- CEF powers plugin overlays and is downloaded at build time.
- libmpv/FFmpeg and the still decoders (libheif/LibRaw) are required for media playback.
- Third-party notices are required in packaged artifacts.

## 5. Linux x64

### Supported distributions

- Ubuntu 22.04/24.04 x64.
- Debian 12/13 x64.
- Other distributions are best-effort; GTK/GL libraries are required.

### Display protocol

- **X11 primary**: intended path for kiosk, autostart, and sleep inhibit.
- **Wayland is not validated.** Flutter runs through GTK; compositor-specific kiosk and
  sleep-inhibit behavior is untested.

### Kiosk and startup

- XDG autostart `.desktop` entry.
- Fullscreen/kiosk controls are wired via `window_manager`.
- Single-instance uses the shared file lock and loopback focus signalling.
- Keep-awake uses `systemd-inhibit --what=sleep:idle` with a `wakelock_plus` fallback. The fallback
  covers idle only.
- Brightness is not standardised: night mode uses a black overlay; there is no panel-brightness
  control.

### Media

- libmpv/FFmpeg are required; hardware decode via VA-API/NVDEC where available.
- CEF on Linux is not runtime validated.

### Packaging

- `scripts/package-linux.sh` builds the release bundle and writes
  `dist/photo-frame-linux-x64.tar.gz`.
- AppImage and `.deb` packaging are not implemented.
- No self-update.

## 6. Desktop equivalents for Android-only requirements

| Android feature | Windows | Linux |
|---|---|---|
| Start on boot | HKCU Run-key entry | XDG autostart |
| Launcher/home replacement | Kiosk/fullscreen only; no launcher replacement | Kiosk/fullscreen only; no launcher replacement |
| Keep screen on | `SetThreadExecutionState` system+display | `systemd-inhibit sleep:idle` + fallback |
| Night-mode brightness | Overlay dimming only | Overlay dimming only |
| Biometric gate | Windows Hello if available; otherwise fail-open | No standard biometric; fail-open |
| Cutouts/insets | OS-reported safe area | OS-reported safe area |
| APK update | Not applicable | Not applicable |
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
| HDR | All platforms output SDR; HDR tone-mapping quality is not guaranteed |
| Android boot | Boot start requires the OEM autostart permission and gates on a battery-optimization exemption. MIUI and some other OEM builds block `BOOT_COMPLETED` without it |
| Updates | Update-check UI, APK download/install, and desktop update flow are not implemented |
| Full kiosk | Close/alt-tab suppression and multi-monitor selection are missing on Windows/Linux |
| Linux runtime | X11, Wayland, kiosk, sleep inhibit, and packaging are not validated |
| Linux packaging | tar.gz only; AppImage and `.deb` are not implemented |
| Linux CEF | No CEF/webview runtime validation |
| Android WebView | System WebView baseline/degradation is not validated on old devices |
| Linux Wayland | Unvalidated; X11 is the intended v1 kiosk path |
| Linux brightness | No universal panel-brightness API; night mode uses an overlay |
| Windows/Linux biometrics | Windows Hello if present; Linux fail-open |
| Desktop launcher | No OS home/launcher replacement equivalent |
| True boot-to-app | Requires OS autologin/kiosk configuration |
| Localization | English only |
| Audio focus | Android device behavior is not validated |
