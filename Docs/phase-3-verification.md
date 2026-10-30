# Phase 3 Verification

Status: Automated and Windows-native verification complete; platform/HDR runtime verification partial
Date: 2026-10-30
Related: [`../Plans/phase-3-media.md`](../Plans/phase-3-media.md),
[`phase-3-stills-plan.md`](phase-3-stills-plan.md)

## 1. Environment

| Item | Value |
|---|---|
| Flutter / Dart | 3.47.8 / 3.13.7 stable |
| Host | Windows 11 x64, Visual Studio 2022 Build Tools, CMake, Ninja, Meson, NASM |
| Native stills | libheif 1.19.7, libde265 1.0.15, dav1d 1.5.0, LibRaw 0.21.3 |
| Native location | `third_party/stills/win-x64/bin` (gitignored); bundled by `windows/CMakeLists.txt` |
| Android | NDK 28.2 installed; no device attached during final verification |
| Linux | No Linux host available |

## 2. Automated results

```text
flutter analyze --no-pub
  -> No issues found

flutter test --no-pub (native DLL directory on PATH)
  -> 242 tests passed, 0 failed, 0 skipped

flutter test --no-pub (without native DLLs)
  -> 240 passed, 2 native tests skipped, 0 failed

flutter build windows --debug --no-pub
  -> built photoframe.exe

flutter build apk --debug --target-platform android-arm64 --no-pub
  -> built app-debug.apk (arm64 media_kit/libmpv present; still .so not bundled)
```

The Windows debug bundle contains `heif.dll`, `libde265.dll`, `dav1d.dll`, `raw.dll`, and
`raw_r.dll`, hash-identical to the locally built files.

## 3. Native still decoding

The live tests decode:

- `test/fixtures/stills/sample.heic` -> 64x48 RGBA (12,288 bytes).
- `test/fixtures/stills/sample.avif` -> 64x48 RGBA (12,288 bytes).
- A temporary real Pentax K-1 DNG (CC0, not committed) -> 7376x4932, 145,513,728 RGBA bytes in
  about 1.5 s, through the LibRaw FFI path.

A LibRaw bitmap-enum bug was found and fixed (`LIBRAW_IMAGE_BITMAP = 2`, not 1). A lossy Adobe DNG
was rejected by LibRaw itself; ProRAW/linear DNG variants remain unverified.

## 4. Implemented and unit/widget-verified

- Video `off`/`staticPreview`/`full`, per-slide duration, mute, pause/resume, next/previous, and the
  Immich playback-stream fallback.
- Live Photo Off/Live/Loop motion with still fallback and global mute.
- Permission gating: videos are skipped when `asset.download` is denied/errored.
- Derived still cache: display-sized JPEG, checksum/profile key, atomic write, reuse, invalidation,
  DB persistence, display precedence, and one-at-a-time isolate derivation.
- Cache schema v3, video originals, Live Photo motion, derived bytes in eviction/stats.
- HDR video tone-mapping defaults (`bt.2446a`, peak computation, SDR target 100) are configured.

## 5. Remaining gaps

1. HDR10/HLG video and 10-bit still tone-mapping were not visually verified or tuned. Android's
   stock media_kit HEVC 10-bit failure from Phase 0 remains; the Immich playback fallback is
   implemented but not device-verified.
2. Linux and Android native still libraries were not built in this session. Scripts exist but are
   unverified; the Android APK therefore falls back to Immich previews for HEIC/AVIF/RAW.
3. Video/audio and Live Photo runtime behavior was not manually verified on Windows or Android
   (audio was not audibly tested; Android audio focus is not explicitly tested).
4. ProRAW/linear DNG quality and embedded-preview fallback were not validated. LibRaw rejects some
   lossy/linear DNG variants; the app falls back to the Immich preview.
5. No long-run player/media-handle leak soak. Widget tests verify disposal, not hours of playback.
6. CI has not been executed. The Windows native build script was run locally; CI only caches
   `third_party/stills`.

The app must not claim true HDR output, HDR10+ dynamic metadata, or Dolby Vision.
