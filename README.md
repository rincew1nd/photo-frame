# Photo Frame

A full-screen photo frame for a self-hosted [Immich](https://immich.app/) library. Photo Frame is a
Flutter app for **Windows x64**, **Linux x64**, and **Android 8.0+ (API 26)**.

- App ID: `com.rincew1nd.photoframe`
- License: [MIT](LICENSE)

## Features

- Connect with an Immich API key or OAuth (PKCE).
- Show albums or a hand-picked set of media.
- Full-screen slideshow with configurable interval, shuffle, transitions, pause/play, and
  next/previous controls.
- Play originals where possible: JPEG, PNG, WebP, GIF, BMP, HEIC/HEIF/AVIF, DNG/RAW, video with
  audio, and Live Photos.
- Ken Burns pan/zoom, contain/cover fitting, and ambient or blurred backgrounds.
- Offline cache with checksum verification, resume, prefetch, LRU eviction, and quota control.
- Interactive HTML/CSS/JS plugins with sandboxing, permissions, drag-and-resize placement, and
  bundled clock, weather, and metadata examples.
- Night mode, keep-awake, start-on-boot, fullscreen or kiosk mode, and a biometric lock for
  library navigation.
- Diagnostics with redacted logs and the Flutter license page.

## Supported platforms

| Platform | Support |
|---|---|
| Windows 10/11 x64 | Supported |
| Linux x64 (Ubuntu/Debian) | Supported; X11 is the primary target, Wayland is untested |
| Android 8.0+ (API 26) | Supported; arm64 and armeabi-v7a |
| iOS, macOS, Raspberry Pi, Linux ARM64 | Out of scope |
| True HDR output | Out of scope; HDR/10-bit sources are tone-mapped to SDR |

## Install

Prebuilt packages are published on the
[GitHub Releases page](https://github.com/rincew1nd/photo-frame/releases).

### Windows

Unzip the release package and run `photoframe.exe`. Keep the executable, its DLLs, and the `data/`
directory together.

### Linux

Extract the release archive and run the `photoframe` binary from the bundle directory.

### Android

Install the APK for your device ABI (`arm64-v8a` or `armeabi-v7a`) and allow installs from the
source you used.

## First-run setup

1. Enter the Immich server URL. Use `https://`.
2. Enter an API key, or choose **OAuth** and sign in.
3. Review the permission summary and connect. The API key needs `user.read`, `album.read`,
   `asset.read`, `asset.view`, and `asset.download`.
4. Select the albums to display and continue to the slideshow.
5. Optionally open settings or manual media selection.
6. Use **Sync now** to populate the offline cache before relying on the frame without a network.

## Build from source

### Requirements

- Flutter **3.47.8** / Dart **3.13.7**.
- **Windows:** Visual Studio with the C++ desktop development workload. Enable Windows Developer
  Mode for plugin symlinks, or keep the project and `PUB_CACHE` on the same volume.
- **Android:** JDK 17, the Android SDK, an API 26+ device or emulator, and `adb`.
- **Linux:** GTK and ninja build tools, `libsecret-1-dev`, and `libjsoncpp-dev`.

### Clone and test

The two patched dependencies are git submodules. Clone them with the project:

```bash
git clone --recurse-submodules https://github.com/rincew1nd/photo-frame.git
cd photo-frame
flutter pub get
flutter analyze
flutter test
```

For an existing clone, run `git submodule update --init --recursive` before `flutter pub get`.

### Build

```bash
flutter build windows --debug
flutter build windows --release
flutter build linux --debug
flutter build linux --release
flutter build apk --debug
flutter build apk --release
```

### Native still decoders

HEIC/HEIF/AVIF and DNG/RAW display from Immich previews unless the native decoders are built:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/fetch-stills-deps.ps1
```

```bash
bash scripts/fetch-stills-deps.sh
bash scripts/build-libheif-android.sh
```

The Windows script requires Windows PowerShell 5.1 (not PowerShell 7) and a Visual Studio 2022
developer environment with CMake, Ninja, Meson, and NASM. Build output is written to the ignored
`third_party/stills/` directory.

### Package releases

Packaging scripts stage artifacts under `dist/`:

```bash
bash scripts/package-windows.sh             # dist/photo-frame-windows-x64.zip
bash scripts/package-linux.sh               # dist/photo-frame-linux-x64.tar.gz
bash scripts/package-android.sh             # split APKs + sha256sums.txt
```

Run them from the repository root with Bash. On Windows use Git Bash, not WSL. Each script accepts
`--skip-build` to package an existing release build. They do not sign or publish artifacts.

## Plugins

Plugins are ZIP bundles containing `plugin.json`, `index.html`, and optional CSS, JavaScript, images,
and settings. They run in a sandbox and receive a read-only snapshot of the current media. Network,
storage, links, and app actions are mediated by the host.

- [Plugin system](Docs/plugins.md)
- [Plugin author guide](Docs/plugin-author-guide.md)

Clock, weather, and metadata ship as bundled example plugins and can be disabled or deleted like any
other plugin.

## Data and security

- Settings are stored as JSON in the application support directory.
- Cached media lives under the application cache directory.
- The Immich API key and OAuth tokens are stored in OS secure storage, never in settings or logs.
- Logs redact API keys, authorization headers, bearer values, and registered secrets.
- Plugins never receive the Immich API key, server URL, or library data.

## Known limitations

- **HDR:** output is SDR. HDR-to-SDR tone-mapping quality is not guaranteed, and HEVC 10-bit HDR10
  playback may fail on Android; use the Immich playback fallback for those files.
- **Native stills:** native HEIC/AVIF/RAW decoding works on Windows when the bundled libheif/LibRaw
  libraries are present. Linux and Android builds require the scripts above.
- **Linux:** X11 is the intended kiosk path. The Linux runtime, Wayland, and Linux CEF have not been
  validated. AppImage and `.deb` packages are not provided.
- **Android start-on-boot:** requires the battery-optimization exemption and the OEM autostart
  permission. Some OEM builds, including MIUI, block `BOOT_COMPLETED` without it.
- **Android plugins:** require system WebView/Chromium 100+. Below that baseline the slideshow runs
  without overlays.
- **Live Photo Bounce:** grayed out on unsupported Android devices; Off, Live, and Loop remain
  available.
- **Kiosk:** Windows/Linux kiosk hides window controls and the cursor, but does not suppress
  close/alt-tab or select a monitor.
- **Updates:** in-app update checks and APK install are not implemented. Use the published release
  artifacts.
- **Localization:** English only.

## Documentation

- [Documentation index](Docs/README.md)
- [Product requirements](REQUIREMENTS.md)
- [Architecture](Docs/architecture.md)
- [Media pipeline](Docs/media.md)
- [Data and cache](Docs/data-cache.md)
- [Platform behavior](Docs/platforms.md)
- [Security](Docs/security.md)
- [Licensing](Docs/licensing.md)
- [Testing and CI](Docs/testing-ci.md)
- [Stack decision](Docs/ADR-0001-stack.md)

## License

MIT. See [LICENSE](LICENSE) and [third-party notices](Docs/licensing.md).
