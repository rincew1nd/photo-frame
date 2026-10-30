# Phase 3 — Native Stills (HEIC / AVIF / RAW) Plan

Scope: decode stills Flutter cannot, cache a display-sized JPEG, render it. No video work here.

## 1. Current state (verified against the working tree)

Done:
- **Decoder seam:** `lib/data/media/still_decoder.dart` (`StillDecoder.decode`, `DecodedRgba`) and
  `preview_only_decoder.dart` (`PreviewOnlyStillDecoder`, returns `null`).
- **Derived cache:** `derived_image_service.dart` — `ensure`, `bucketFor` (320 step, clamp 320..3840),
  `cacheKeyFor` (`v1-<checksum8>-L<bucket>`), `<assetId>-<key>.jpg`, `.part` → rename.
- **Cache/slideshow wiring:** `CacheSyncService.applyDerivedImage` persists path/size;
  `SlideshowController.refreshCachedAsset` plus a one-at-a-time `ensureDerived` queue; `displayFileFor`
  returns derived → original → thumbnail for decodable stills and derived → thumbnail otherwise.
- **Isolate worker:** `lib/data/media/derived_image_worker.dart` opens libraries per worker and sends
  back only path/size; decode is eager, so the preview shows until the derived file is ready.
- **FFI bindings:** `native/heif_bindings.dart`, `native/libraw_bindings.dart`, `native_still_decoder.dart`.
- **Provider selection:** `stillDecoderProvider` and the worker use
  `NativeStillDecoder.tryCreate() ?? PreviewOnlyStillDecoder()`; any library failure logs once and falls
  back to previews.
- **Scripts:** `scripts/fetch-stills-deps.ps1`, `fetch-stills-deps.sh`, `build-libheif-android.sh`;
  `third_party/stills/` is gitignored and CI-cached; Windows/Linux CMake bundle `*.dll` / `*.so*`.
- **Tests:** derived-service/worker tests, binding tests, `native_still_decoder_test.dart`, and live
  decode tests over `test/fixtures/stills` (HEIC/AVIF, gated by library availability).

Verified: Windows native decode of generated HEIC/AVIF fixtures and a real Pentax K-1 DNG (7376x4932)
decoded in about 1.5 s. LibRaw initially failed with a bitmap enum bug; fixed, and it now decodes.

Pending:
- Linux and Android native builds/runtime: scripts exist but are unverified.
- HDR/10-bit visual tuning; ProRAW quality validation.
- DNG fixture provenance/licensing, and native measurements on reference hardware (§5 targets, not results).
- `derived_images` table stays unimplemented by decision — the checksum and filename key cover invalidation.

## 2. Native library strategy

| Component | Version | License | Role |
|---|---|---|---|
| libheif | 1.19.7 | LGPL-3.0 | HEIC/AVIF container + decode API |
| libde265 | 1.0.15 | LGPL-3.0 | HEVC/HEIC codec |
| dav1d | 1.5.0 | BSD-2-Clause | AV1/AVIF codec |
| LibRaw | 0.21.3 | LGPL-2.1 (CDDL alt.) | RAW (CR2/NEF/ARW/DNG/ProRAW) |

**Dynamic linking only**, one DLL/.so per library, never merged into `photoframe.exe`. Build libheif with
`-DWITH_LIBDE265=ON -DWITH_DAV1D=ON`; no x265, no AOM, no encoders (avoids GPL and extra patent surface).
Ship upstream LICENSE files via `third_party/stills/licenses/` → `bundle/licenses/stills/`, plus a
`Docs/licensing.md` paragraph in the native step.

Bundling:
- Windows — `windows/CMakeLists.txt`: `install(FILES <stills>/win-x64/bin/{heif,de265,dav1d,raw}.dll DESTINATION "${CMAKE_INSTALL_PREFIX}")`. `DynamicLibrary.open('heif.dll')` finds it next to the exe.
- Linux — `linux/CMakeLists.txt`: `install(FILES <stills>/linux-x64/lib/*.so* DESTINATION "${CMAKE_INSTALL_PREFIX}/lib")`; `$ORIGIN/lib` is already set (`linux/CMakeLists.txt:17`). Open `libheif.so.1`.
- Android — `android/app/src/main/jniLibs/{arm64-v8a,armeabi-v7a}/lib*.so`; Gradle packages `jniLibs` automatically. Open `libheif.so`.

Scripts are idempotent, SHA-256 verified, skipped when the target exists: `scripts/fetch-stills-deps.ps1`
(win-x64: prebuilt de265/dav1d, CMake libheif + LibRaw), `scripts/fetch-stills-deps.sh` (linux-x64, same shape),
`scripts/build-libheif-android.sh` (NDK, both ABIs, plus LibRaw). Output lives in `third_party/stills/` (`bin/`,
`lib/`, `include/`), gitignored. CI: `actions/cache` on `third_party/stills`, keyed by `hashFiles('scripts/fetch-stills-deps.*')`.

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
1. **Persistence.** Add `CacheSyncService.applyDerivedImage(String assetId, {required String path, required int sizeBytes})` → `store.upsertAsset(asset.copyWith(...))`, returning the updated asset.
2. **Isolate.** Wrap the call site in `Isolate.run(() => ensure(...))` so decode, resize, encode, `.part`
   write and rename stay off the UI isolate. `DynamicLibrary` handles are not sendable, so the native decoder
   opens its libraries per isolate (dlopen is ~1 ms), and only `(path, sizeBytes)` comes back.
3. **Wiring.** `displayFileFor` order becomes derived → original → thumbnail for non-decodable MIME, and
   derived → original → thumbnail for the rest. Queue derivation for non-`isDecodableImage` assets from
   `SlideshowController` (one at a time), render the thumbnail immediately, then `refreshCachedAsset(String id)`
   swaps that entry in `state.cached` — no album reload, no sync, no flash.

Reuse check: `_cached` should require only "file exists and length > 0"; the key is in the filename, so no
extra invalidation logic is needed.

Bucket source at the call site is `MediaQuery.sizeOf(context).longestSide * devicePixelRatio` through
`DerivedImageService.bucketFor` (320..3840); 320 stays the floor so small windows do not upscale from a blurrier derived file.

## 5. Test strategy

Done: `derived_image_service_test.dart`, `derived_image_worker_test.dart`,
`preview_only_decoder_test.dart`, `native/heif_bindings_test.dart`, `native/libraw_bindings_test.dart`,
`native/native_still_decoder_test.dart`, and gated `native/native_still_decoder_live_test.dart`
(`sample.heic`/`sample.avif`, 64x48, asserts RGBA dimensions and non-zero pixels, skips without libraries).
Also covered: `applyDerivedImage` persistence, `displayFileFor` precedence, and `refreshCachedAsset`.

Pending:
- `sample.dng` fixture (<64 KB) with recorded provenance/licensing.
- One gated measurement test: 12 MP HEIC decode+encode under 1200 ms desktop, derived JPEG ≤ 900 KB at the
  1920 bucket, peak RSS delta ≤ 220 MB for a 24 MP RAW. Run on reference hardware.

## 6. Ordered implementation steps

1. **Done (`afd5f47`):** `StillDecoder` seam, `PreviewOnlyStillDecoder`, `DerivedImageService` with tests.
2. **Done (`2c9b615`):** `applyDerivedImage`, `refreshCachedAsset` + one-at-a-time derivation queue,
   `displayFileFor`, isolate worker. HEIC behavior unchanged (preview decoder returns `null`).
3. **Done (`fc7d169`):** FFI bindings, `NativeStillDecoder`, provider selection, Windows native decode
   verified with generated HEIC/AVIF and a real Pentax K-1 DNG.
4. **Done:** build scripts, `.gitignore` entry, CI cache, Windows DLL bundling, Linux `.so` install
   rules, Android `jniLibs` output script.
5. **Pending:** run `scripts/fetch-stills-deps.sh` on Linux and confirm `ldd` resolves `libheif.so.1` via
   `$ORIGIN/lib`.
6. **Pending:** run `scripts/build-libheif-android.sh`, confirm both ABIs land in the APK, and verify
   decode on a device.
7. **Pending:** native measurement tests on reference hardware; DNG fixture with provenance/licensing;
   ProRAW quality validation; license copies and the `Docs/licensing.md` / `Docs/data-cache.md` notes.

## 7. Risks

- **Licensing:** libheif/libde265 are LGPL-3.0, LibRaw LGPL-2.1. Dynamic linking keeps relinking possible;
  static linking would force object-file distribution. Keep x265 and AOM out of every build script.
- **ProRAW quality:** ProRAW is a DNG with non-Bayer data plus an embedded preview; LibRaw can return flat
  or wrong-toned output. If `libraw_process` fails or output is degenerate, fall back to the Immich preview — no Apple pipeline.
- **ABI size:** the four libraries total ~12–18 MB per ABI, doubled for two ABIs. If APK size matters, drop
  `armeabi-v7a` first — cheapest cut, affects almost no real frames.
- **Memory spikes:** full-res RGBA of 50 MP is ~200 MB. Keep resize+encode+write inside the isolate, rely on
  `half_size`, and never send pixels back across the isolate boundary.
- **Thread safety:** LibRaw handles and their error buffer are not shareable; a shared handle across isolates
  corrupts state. Enforce one handle per decode in `NativeStillDecoder`.
- **CI time:** a cold libheif build adds ~4–6 min. Cache `third_party/stills/` keyed on the scripts and keep
  native builds out of PR-required checks, matching the existing `build-windows` pattern.
- **Cache bloat:** 3840 derived JPEGs can rival originals; evict derived before originals (documented policy).
