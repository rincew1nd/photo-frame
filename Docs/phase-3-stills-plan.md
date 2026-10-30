# Phase 3 — Native Stills (HEIC / AVIF / RAW) Plan

Scope: decode stills Flutter cannot, cache a display-sized JPEG, render it. No video work here.

## 1. Current state (verified against the working tree)

Already in place in this slice:
- `lib/data/media/still_decoder.dart` — `StillDecoder.decode(String path, {required int maxLongSide})`, `DecodedRgba{bytes, width, height}`.
- `lib/data/media/preview_only_decoder.dart` — `PreviewOnlyStillDecoder`, returns `null`.
- `lib/data/media/derived_image_service.dart` — `DerivedImageService.ensure({source, assetId, checksum, targetLongSide})`, `bucketFor` (320 step, clamp 320..3840), `cacheKeyFor` (`v1-<checksum8>-L<bucket>`), `<assetId>-<key>.jpg`, `.part` → rename.
- Tests: `test/data/media/derived_image_service_test.dart`, `test/data/media/preview_only_decoder_test.dart`.
- `image: ^4.12.0` is now a direct dependency; `ffi` is transitive only.

Committed foundations:
- `derived/` is seeded by `cacheSubdirectories` (`lib/platform/paths.dart:7`) for both `AppPaths` impls.
- `CachedAsset.derivedImagePath` / `derivedImageSizeBytes` exist, persist as `derived_image_path` /
  `derived_image_size_bytes` (`lib/data/cache/app_database.dart`), count in stats, are deleted by
  `CacheSyncService._deleteFiles`, and `resolve()` already prefers derived → original → thumbnail.

Still missing:
- Nothing writes `DerivedImage` back to the DB; no caller invokes `ensure`.
- Decode+resize+encode runs on the caller isolate (`// ponytail:` comment in the service).
- `displayFileFor` (`lib/features/slideshow/slideshow_screen.dart:611`) still returns the thumbnail for
  any MIME outside jpeg/png/webp/gif/bmp.
- No native libs, `scripts/`, `third_party/stills/`, `jniLibs/`, or CI cache.
- `derived_images` table is documented in `Docs/data-cache.md:93` but unimplemented. **Decision: keep it
  unimplemented** — `asset.checksum` plus the key in the filename covers invalidation.

## 2. Native library strategy

| Component | Version | License | Role |
|---|---|---|---|
| libheif | 1.19.7 | LGPL-3.0 | HEIC/AVIF container + decode API |
| libde265 | 1.0.15 | LGPL-3.0 | HEVC/HEIC codec |
| dav1d | 1.5.0 | BSD-2-Clause | AV1/AVIF codec |
| LibRaw | 0.21.3 | LGPL-2.1 (CDDL alt.) | RAW (CR2/NEF/ARW/DNG/ProRAW) |

**Dynamic linking only**, one DLL/.so per library, never merged into `photoframe.exe`. Build libheif with
`-DWITH_LIBDE265=ON -DWITH_DAV1D=ON`; no x265, no AOM, no encoders (avoids GPL and extra patent surface).
Ship upstream LICENSE files under `third_party/stills/licenses/`, copy to `bundle/licenses/stills/`, and add
one paragraph to `Docs/licensing.md` in the native step.

Bundling:
- Windows — `windows/CMakeLists.txt`: `install(FILES <stills>/win-x64/bin/{heif,de265,dav1d,raw}.dll DESTINATION "${CMAKE_INSTALL_PREFIX}")`. `DynamicLibrary.open('heif.dll')` finds it next to the exe.
- Linux — `linux/CMakeLists.txt`: `install(FILES <stills>/linux-x64/lib/*.so* DESTINATION "${CMAKE_INSTALL_PREFIX}/lib")`; `$ORIGIN/lib` is already set (`linux/CMakeLists.txt:17`). Open `libheif.so.1`.
- Android — `android/app/src/main/jniLibs/{arm64-v8a,armeabi-v7a}/lib*.so`; Gradle packages `jniLibs` automatically. Open `libheif.so`.

Scripts, each idempotent and SHA-256 verified, skipping when the target exists:
- `scripts/fetch-stills-deps.ps1` — win-x64: fetch de265/dav1d prebuilt binaries, build libheif + LibRaw with CMake.
- `scripts/fetch-stills-deps.sh` — linux-x64, same shape.
- `scripts/build-libheif-android.sh` — NDK toolchain for both ABIs, plus LibRaw with the same toolchain.

Output lives in `third_party/stills/` (`bin/`, `lib/`, `include/`); add `/third_party/stills/` to
`.gitignore`. CI: `actions/cache` on `third_party/stills`, keyed by `hashFiles('scripts/fetch-stills-deps.*')`.

Fallback: `NativeStillDecoder.isAvailable` opens the libraries once per process. Any failure → register
`PreviewOnlyStillDecoder`, log one warning, thumbnails keep rendering. Never throw into the slideshow.

## 3. Minimum FFI surface

libheif (`lib/data/media/native/libheif_ffi.dart`): `heif_context_alloc`,
`heif_context_read_from_file`, `heif_context_get_primary_image_handle`,
`heif_image_handle_get_width/height`, `heif_decode_image` (`heif_colorspace_RGB`,
`heif_chroma_interleaved_RGBA`, 32-bit), `heif_image_get_plane_readonly(heif_channel_interleaved)`,
`heif_image_release`, `heif_image_handle_release`, `heif_context_free`.

LibRaw (`lib/data/media/native/libraw_ffi.dart`): `libraw_init`, `libraw_open_file`, `libraw_unpack`,
`libraw_get_cam_mul`, `libraw_set_user_mul`, `libraw_process`, `libraw_make_mem_image`,
`libraw_processed_image_free`, `libraw_close`, `libraw_strerror`.

Memory ownership:
- heif: `heif_context_alloc` freed by `heif_context_free`; handles/images are refcounted — copy the
  interleaved RGBA plane into a `Uint8List` **before** `heif_image_release`. `read_from_file` is lazy.
- LibRaw: `libraw_init(0)` owns `libraw_data_t`; `libraw_make_mem_image` returns a malloc'd buffer freed
  with `libraw_processed_image_free`; `libraw_close` releases the handle. Copy out before freeing.
- `libraw_set_user_mul` takes 4 floats (cam_mul R,G,B,G). There is no `use_camera_wb` setter in the C API,
  so read `libraw_get_cam_mul` and re-apply it explicitly.
- Thread safety: one handle per decode, never shared or reused concurrently. LibRaw's error string is
  thread-local — call `libraw_strerror` immediately after a non-zero return.

## 4. Dart architecture

`NativeStillDecoder implements StillDecoder`: libheif for `image/heic|heif|avif`, LibRaw for everything
else; if `maxLongSide` is well below source size, use it to skip work (LibRaw `half_size = 1` when source
longest side > 2× `maxLongSide`, else `0`).

Three gaps to close on top of the existing service:
1. **Persistence.** Add `CacheSyncService.applyDerivedImage(String assetId, {required String path,
   required int sizeBytes})` → `store.upsertAsset(asset.copyWith(...))` returning the updated asset.
2. **Isolate.** Wrap the call site in `Isolate.run(() => ensure(...))` so decode, resize, encode, `.part`
   write and rename stay off the UI isolate. `DynamicLibrary` handles are not sendable, so the native decoder
   opens its libraries per isolate (dlopen is ~1 ms), and only `(path, sizeBytes)` comes back.
3. **Wiring.** `displayFileFor` order becomes derived → original → thumbnail for non-decodable MIME, and
   derived → original → thumbnail for the rest. Queue derivation for non-`isDecodableImage` assets from
   `SlideshowController` (one job at a time), render the thumbnail immediately, then
   `refreshCachedAsset(String id)` swaps just that entry in `state.cached` — no album reload, no sync, no flash.

Reuse check: rewrite `_cached` to require only "file exists and length > 0". The key is already in the
filename, so re-decoding the cached JPEG on every reuse is wasted work. Filename/key mismatch (checksum or
bucket change) already produces a different path, so no extra invalidation logic is needed.

Bucket source at the call site: `MediaQuery.sizeOf(context).longestSide * devicePixelRatio`, passed through
`DerivedImageService.bucketFor` (320..3840). Keep 320 as the floor so small windows do not upscale from a
blurrier derived file than needed.

## 5. Test strategy

Existing: `derived_image_service_test.dart` (bucket rounding, key format, fake decoder, `.part` cleanup) and
`preview_only_decoder_test.dart`. Keep the private `_FakeStillDecoder` there and add a shared
`test/support/fake_still_decoder.dart` only if a third test needs it.

Add:
- `applyDerivedImage` upserts the path and byte count and returns the updated asset; the row round-trips
  through `DriftCacheStore`.
- `displayFileFor` precedence table: derived wins, missing derived falls back to original, video stays on
  thumbnail.
- `refreshCachedAsset` replaces one entry and leaves list order intact.
- `native_still_decoder_test.dart`, gated by `stillsNativeAvailable()` and `skip: 'native stills not built'`
  so a fresh clone is green; assert RGBA dimensions, not pixel equality.
- Fixtures: `test/fixtures/stills/sample.heic` (<16 KB) and `sample.dng` (<64 KB), checked in, with a test
  asserting those size limits.
- One gated measurement test: 12 MP HEIC decode+encode under 1200 ms desktop, derived JPEG ≤ 900 KB at the
  1920 bucket, peak RSS delta ≤ 220 MB for a 24 MP RAW.

## 6. Ordered implementation steps

1. **Slice 2, still no native libs:** `applyDerivedImage` in `lib/data/cache/cache_sync_service.dart`;
   `refreshCachedAsset` and the one-at-a-time derivation queue in
   `lib/features/slideshow/slideshow_controller.dart`; `displayFileFor` in
   `lib/features/slideshow/slideshow_screen.dart`; `Isolate.run` at the call site. Tests from §5 except the
   native one. Real HEIC behavior is unchanged (preview-only decoder returns `null`) — pure plumbing.
2. `scripts/fetch-stills-deps.ps1`, `scripts/fetch-stills-deps.sh`; `.gitignore` entry; `actions/cache` step
   in `.github/workflows/ci.yml`.
3. `lib/data/media/native/libheif_ffi.dart`, `libraw_ffi.dart`, `native_still_decoder.dart`; add
   `ffi: ^2.2.0` to `pubspec.yaml` dependencies.
4. Windows bundling in `windows/CMakeLists.txt`; confirm `heif.dll` lands beside `photoframe.exe`.
5. Linux bundling in `linux/CMakeLists.txt`; confirm `ldd` resolves `libheif.so.1` via `$ORIGIN/lib`.
6. `scripts/build-libheif-android.sh` + `jniLibs/` output; confirm the APK contains both ABIs.
7. Native + measurement tests, fixtures, license copies, and the `Docs/licensing.md` /
   `Docs/data-cache.md` note (drop or mark the `derived_images` row superseded).

## 7. Risks

- **Licensing:** libheif/libde265 are LGPL-3.0, LibRaw LGPL-2.1. Dynamic linking keeps relinking possible;
  static linking would force object-file distribution. Keep x265 and AOM out of every build script.
- **ProRAW quality:** ProRAW is a DNG with non-Bayer data plus an embedded preview; LibRaw can return flat
  or wrong-toned output. If `libraw_process` fails or output is degenerate, fall back to the Immich preview.
  Do not attempt Apple's pipeline.
- **ABI size:** the four libraries total ~12–18 MB per ABI, doubled for two ABIs. If APK size matters, drop
  `armeabi-v7a` first — cheapest cut, affects almost no real frames.
- **Memory spikes:** full-res RGBA of 50 MP is ~200 MB. Keep resize+encode+write inside the isolate, rely on
  `half_size`, and never send pixels back across the isolate boundary.
- **Thread safety:** LibRaw handles and their error buffer are not shareable; a shared handle across isolates
  corrupts state. Enforce one handle per decode in `NativeStillDecoder`.
- **CI time:** a cold libheif build adds ~4–6 min. Cache `third_party/stills/` keyed on the scripts and keep
  native builds out of PR-required checks, matching the existing `build-windows` pattern.
- **Cache bloat:** derived JPEGs at 3840 can rival originals. Evict derived before originals (already the
  documented policy) and cap the derived dir at one file per asset by deleting stale keys on re-derive.
