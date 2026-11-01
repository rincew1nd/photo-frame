# Photo Frame

A full-screen photo frame for a self-hosted [Immich](https://immich.app/) library. Photo Frame is a
cross-platform Flutter application for **Windows x64**, **Linux x64**, and **Android 8+ (API 26+)**.

- App ID: `com.rincew1nd.photoframe`
- Version: `1.0.0+1`
- License: [MIT](LICENSE)

## Current scope

Phases 1–2 are implemented. Phase 3 video, Live Photo, and native still decoding are implemented with
verification gaps (HDR, Linux/Android native builds, broader runtime testing). Phase 4 is not
started. Phase 5 is in progress: night brightness, diagnostics, start-on-boot, desktop kiosk and
keep-awake, single-instance focus, and packaging scripts are implemented; Windows default and kiosk
launches are verified. Windows fullscreen now uses a Win32 popup style with monitor bounds and native focus; a manual Win32 check hid the taskbar. Final app-level taskbar/cursor confirmation and sign-in autostart remain pending. Updates,
full kiosk lockdown, Linux runtime validation, and localization remain. Audio focus is implemented and
unit/widget tested; Android device verification is pending.

The app can connect to Immich, select albums or individual media, cache media for offline playback,
and run a full-screen slideshow with overlays and night mode. HEIC/HEIF/AVIF and DNG/ProRAW decode
natively through bundled libheif/LibRaw when those native libraries are present; without them the app
falls back to Immich previews.

Implemented:

- API-key and OAuth (PKCE) setup.
- Album selection.
- Manual media selection, with a biometric lock when the platform supports it.
- Slideshow with configurable interval, shuffle, transitions, pause/play, next/previous, and progress.
- Original-first display for JPEG, PNG, WebP, GIF, and BMP. Native decoding for HEIC/HEIF/AVIF
  (libheif) and DNG, including ProRAW where LibRaw supports the variant, with a display-sized derived
  JPEG cache and the Immich preview fallback; videos use cached originals for playback.
- Video playback with audio and mute (`VideoPlaybackMode.full`); `off` and `staticPreview` remain.
- Live Photo Off/Live/Loop/Bounce motion playback with a still fallback.
- Ken Burns pan/zoom, contain/cover fitting, and adaptive backgrounds (ambient glow or blurred cover).
- Disk cache with checksum verification, resume, LRU eviction, quota, and offline playback.
- Clock, weather, and EXIF overlays; settings screens.
- Night mode with overlay dimming, pause, hidden overlays, and Android window brightness
  (`1 - dimOpacity`) that restores when night mode ends or the slideshow closes.
- Start-on-boot and launcher plumbing: Android `BootReceiver` + HOME intent, Windows Run key, and
  Linux XDG autostart. Android boot requires a battery-optimization exemption and the OEM autostart
  permission; the Automation screen gates start-on-boot on the exemption and links to the OEM
  autostart and Home app settings.
- Desktop kiosk mode (fullscreen, always-on-top, skip taskbar, fixed window, hidden cursor),
  keep-awake, and second-instance focus. Windows default and kiosk launches are verified; visual
  kiosk behavior is pending.
- About & diagnostics: version/build, plugin API v1, platform/OS, cache stats, redacted logs,
  error count/copy, and the Flutter license page.
- Settings schema v3 with start-on-boot, fullscreen, kiosk, and update-check fields.
- Packaging scripts for Windows ZIP, Linux tar.gz, and Android split APKs with sha256sums.
- Logging with secret redaction.
- Single-instance lock, wake-lock, and fullscreen.

Not implemented yet:

- **Phase 3 (remaining):** HDR-to-SDR verification and tuning, native library builds for Linux and
  Android (scripts exist but are unverified), and broader platform runtime testing. Video playback,
  Live Photo motion, and Windows native still decoding are implemented.
- **Phase 4:** plugin host, WebView baseline checks, HTML/CSS/JS overlays, and migration of the
  current clock/weather/metadata overlays into bundled plugins.
- **Phase 5:** update-check UI and APK download/install (blocked on a release channel and keystore),
  full kiosk lockdown (close/alt-tab suppression and multi-monitor selection), Linux AppImage/deb
  and runtime validation, and localization completion. Audio focus is implemented and unit/widget\n  tested; Android device verification is pending.

Android release builds currently use the debug signing key; no GitHub release channel or release
keystore is configured.

## How it works

- UI: Flutter with Riverpod state management and go_router navigation.
- Immich API: a Dio-based client using `x-api-key` or OAuth bearer tokens.
- Metadata cache: Drift/SQLite.
- Media files: stored under the platform application cache directory.
- Secrets: the Immich API key and OAuth tokens are kept in OS secure storage.
- Settings: a JSON file in the application support directory.

The slideshow flow is: **connect → albums → cache sync → slideshow → overlays**. Sync downloads a
preview-sized image for every asset, an original for stills, and video originals plus Live Photo
motion for playback. At display time, formats Flutter can decode (JPEG, PNG, WebP, GIF, BMP) use the
original with the preview as a fallback; other still formats use a display-sized derived JPEG from
the native decoders when available, otherwise the Immich preview. Videos play from the cached
original with audio and mute control, and Live Photos play motion (Off/Live/Loop/Bounce) with a
still fallback. Bounce plays the motion forward, then reverses by seeking backward in short steps
while the slide is visible (it may be choppy); audio is not played during the reverse pass.

## Requirements and toolchains

- Flutter **3.47.8** / Dart **3.13.7**.
- **Windows:** Visual Studio with the C++ desktop development workload. Enable Windows Developer Mode
  for plugin symlinks, or keep the project and `PUB_CACHE` on the same volume.
- **Android:** an API 26+ device or emulator, Java 17, and `adb`.
- **Linux:** GTK and ninja build tools, plus `libsecret-1-dev` and `libjsoncpp-dev`.

The repository vendors `third_party/flutter_secure_storage_windows` and overrides the package path in
`pubspec.yaml`. This removes the Windows native plugin's ATL dependency and uses the package's Dart
FFI Windows implementation with Windows Credential Manager instead.

Localization is generated by the Flutter tool from `lib/l10n/app_en.arb`; do not edit the generated
`lib/l10n/app_localizations*.dart` files by hand.

## Build

```bash
flutter pub get
flutter analyze
flutter test

flutter build windows --debug
flutter build windows --release
flutter build apk --debug
flutter build apk --release
flutter build linux --debug
flutter build linux --release
```

Release packaging scripts stage artifacts under `dist/`:

```bash
bash scripts/package-windows.sh             # dist/photo-frame-windows-x64.zip
bash scripts/package-linux.sh               # dist/photo-frame-linux-x64.tar.gz
bash scripts/package-android.sh             # split APKs + sha256sums.txt
```

On Windows, run the packaging scripts with Git Bash (not WSL). `scripts/fetch-stills-deps.ps1`
requires Windows PowerShell 5.1 (not PowerShell 7). Each packaging script also accepts a
`--skip-build` flag to package an existing release build. They do not sign or publish artifacts.
Windows default and kiosk launches and the rebuilt ZIP are verified locally. Fullscreen now uses a
Win32 popup style with monitor bounds and native focus; a manual Win32 check hid the taskbar. Final
app-level taskbar/cursor confirmation and sign-in autostart still need manual checks. Linux was never
run in this environment. Android release builds are debug-signed, and the update flow is not implemented.

## Install and run

### Windows

After building, run the executable and keep its `data/` directory and DLLs beside it:

- Debug: `build/windows/x64/runner/Debug/photoframe.exe`
- Release: `build/windows/x64/runner/Release/photoframe.exe`

The release build launches and stays running with kiosk on or off after the `waitUntilReadyToShow()`
fix: `setSkipTaskbar` needs the plugin's `ITaskbarList3` pointer, which is null until that call
(`window_manager_plugin.dll`, 0xC0000005/0xa005).

For development, use:

```bash
flutter run -d windows
```

### Android

1. Enable USB debugging on the device and connect it.
2. Confirm the device is visible with `adb devices`.
3. Install and launch the app:

```bash
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

Launch **Photo Frame** from the home screen. The minimum supported version is Android 8.0 (API 26).
For a release build, use `build/app/outputs/flutter-apk/app-release.apk`, or the split-per-ABI
outputs (for example `app-arm64-v8a-release.apk`) if you built with `--split-per-abi`. Release
builds currently use the debug signing key.

For unattended start, open **Settings > Automation** and grant the battery-optimization exemption,
the OEM autostart permission, and optionally select Photo Frame as the Home app. Start on boot stays
disabled until the battery exemption is confirmed. The test device is not yet exempt.

### Linux

Run the bundle directly:

- Debug: `build/linux/x64/debug/bundle/photoframe`
- Release: `build/linux/x64/release/bundle/photoframe`

For development, use:

```bash
flutter run -d linux
```

## First-run setup

1. Enter the Immich server URL. Use `https://`.
2. Enter an API key, or choose **OAuth** and sign in. The API key needs these permissions:
   `user.read`, `album.read`, `asset.read`, `asset.view`, and `asset.download`.
3. Review the permission summary and connect.
4. Select the albums to display and continue to the slideshow.
5. Optionally open settings or manual media selection.
6. Use **Sync now** to populate the offline cache before relying on the frame without a network.

## Data and security

- Settings are stored as JSON in the application support directory.
- Cached media lives under the application cache directory.
- The API key and OAuth tokens are stored in OS secure storage and are never written to settings or
  logs.
- Logs redact API keys, authorization headers, bearer values, and registered secrets.

## Project layout

```
lib/app        bootstrap, routing, theme, providers
lib/core       shared models, clock, failures, logging
lib/data       Immich client, cache, settings, secure storage, weather
lib/domain     slideshow, media filters, Ken Burns, night mode
lib/features   setup, albums, slideshow, settings, media selection
lib/platform   paths and platform services
lib/l10n       ARB source and generated localizations
test           unit and widget tests
Docs           technical documentation and evidence
Plans          phase plans
third_party    vendored packages
```

See [Docs/architecture.md](Docs/architecture.md) for the layer rules.

## Tests and CI

`flutter analyze` and `flutter test` must pass. Current baseline: `flutter analyze` clean, 261 passed,
2 native skips (without DLLs). `.github/workflows/ci.yml` runs analyze/test on every push and pull
request, and builds Android, Windows, and Linux on non-pull-request runs. Tiny still fixtures under
`test/fixtures/stills` drive gated native decode tests, which skip when the native libraries are not
built.

## Limitations, roadmap, and troubleshooting

- **HTTP 308 redirect:** the Immich server may redirect plain HTTP to HTTPS. Enter the `https://` URL.
- **Windows symlink error:** if plugin symlink creation fails, enable Developer Mode or keep the
  project and `PUB_CACHE` on the same volume. (The vendored secure-storage package avoids ATL, but
  Flutter still uses symlinks for plugins.)
- **Live Photo Bounce:** on Android, only Bounce is grayed out with **Device is not supported**;
  Off, Live, and Loop remain available. A saved Bounce mode falls back to Loop during playback.
- **HEIC/AVIF/RAW:** native decode is used when the bundled libheif/LibRaw libraries are present;
  otherwise the Immich preview is shown. Windows native HEIC/AVIF/DNG decode was verified locally;
  Linux and Android require the build scripts to be run on those platforms.
- **Empty slideshow:** select at least one album and run **Sync now**.
- **Linux:** build and runtime behavior has not been verified; no Linux host was available. XDG
  autostart, kiosk, sleep inhibit, and tar.gz packaging are implemented but unvalidated.
- **Android boot:** a real reboot on Xiaomi/MIUI Android 12 with `start_on_boot=true` did not launch
  the app (`BOOT_COMPLETED: process is not permitted to auto start`). Grant the MIUI autostart
  permission and the battery-optimization exemption; the test device is not exempt and start-on-boot
  is gated on it. Shell broadcasts are blocked on non-rooted devices. The HOME role is selected in
  Android settings.
- **Android signing/updates:** release APKs use the debug signing key; no release keystore or GitHub
  release channel is configured. Update-check UI and APK download/install are not implemented.
- **Kiosk:** Windows/Linux kiosk is implemented to hide window controls and the cursor, but does not
  suppress close/alt-tab or select a monitor. Windows default and kiosk launches are verified; visual
  kiosk behavior (always-on-top, taskbar hiding, cursor) is not manually verified.
- **Videos:** full playback with audio is implemented; HDR-to-SDR tone-mapping is not yet verified
  and native codec builds remain pending.
- **Plugins/WebView:** Phase 4 is not started; WebView baseline checks, plugin degradation, and CEF
  diagnostics are pending.
- **Localization:** English-only; final locale list undecided. Audio focus is implemented and
  unit/widget tested; Android device verification is pending.
- **True HDR:** out of scope for v1; HDR sources are decoded to SDR, and tone-mapping is not yet
  verified.

## Documentation

- [Documentation index](Docs/README.md)
- [Product requirements](REQUIREMENTS.md)
- [Phase plans](Plans/README.md)
- [Architecture](Docs/architecture.md)
- [Platform support](Docs/platforms.md)
- [Platform checklists](Docs/platform-checklists.md)
- [Phase 1/2 verification](Docs/phase-1-2-verification.md)
- [Phase 0 spike results](Docs/spike-0-results.md)

## License

MIT. See [LICENSE](LICENSE).
