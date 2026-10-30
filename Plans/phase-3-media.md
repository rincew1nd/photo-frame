# Phase 3 — Video, Audio, Live Photos, and Original Stills

Status: In progress
Depends on: Phase 2 (done) plus the post-Phase-2 cleanup
Unblocks: Phase 4

Baseline at revision: `flutter analyze` clean, 182 tests passing, no commits. Windows and Android
debug builds were verified before the cleanup; Linux was never verified.

## Goal

Deliver the original-media pipeline: videos with audio, Live Photos, and HEIC/AVIF/DNG/ProRAW stills,
including HDR-to-SDR tone-mapping and graceful fallbacks.

## Starting point (after Phase 2 and cleanup)

- Settings schema v2 exists: `PlaybackSettings` has `intervalSeconds`, `shuffle`, `transition`,
  `muted`, `videoPlaybackMode`, and a **global** `livePhotoMode`. `videoPlaybackMode.off` and
  `staticPreview` work; `full`, `speedUp`, `highlights`, and `slice` are disabled placeholders.
  `livePhotoMode.off` works; `live` and `loop` are disabled placeholders.
- `CustomizationProfile` matches media type + aspect bucket and provides
  fit/imageMotion/adaptiveBackground/panStrength. Image fit is authoritative; pan/motion apply only
  with Cover. Live Photo mode is global, not per-aspect.
- The older multi-select type/aspect filter model is not in the current code. Video/Live Photo gating
  is via playback modes plus manual media selection.
- Cache is still photo-only: videos are not downloaded as originals, and Live Photo motion is not
  downloaded. Only `originals/` and `thumbnails/` directories exist. `CachedAsset` has no motion or
  derived-image paths. Eviction/stats count original + thumbnail only.
- Slideshow placeholders: video shows `_VideoLabel`/static preview, Live Photo shows `_LivePhotoHint`,
  the mute control is disabled, and `displayFileFor` falls back to Immich previews for videos and
  HEIC/AVIF/RAW.
- Cleanup removed `offline_media_resolver.dart` and `core/result.dart`; resolution is through
  `CacheSyncService`/`CacheStore`, and failures use `AppFailure`. Reuse `fileIfExists`,
  `CachedAsset.isDecodableImage`, `ImmichClient.displayUrl`, and `mediaKindLabel`.
- `pubspec.yaml` has no `media_kit` or native decoder tooling. Phase 3 must add and pin them.
- Spike constraints remain: Android stock media_kit fails HEVC 10-bit HDR10; libheif/LibRaw are
  absent; HDR tone-mapping is unverified; audio was not audibly tested.

## Scope

### Video

- Implement only `VideoPlaybackMode.full`; preserve `off` and `staticPreview`.
- `speedUp`/`highlights`/`slice` stay disabled and out of scope for this phase.
- media_kit/libmpv player abstraction: local cached original first, then the Immich original URL
  with auth headers.
- Hardware decode where available; software fallback.
- Per-asset duration and auto-advance for video; pause/resume/next/previous/progress.
- Video fit from the resolved profile; no Ken Burns/pan on video.

### Audio

- Wire the existing `muted` setting; volume handling and Android audio focus.
- Stop/dispose audio on slide change; no background playback.

### Live Photos

- Use the existing cached `livePhotoVideoId`; download the motion file.
- Use the global `PlaybackSettings.livePhotoMode` values Off/Live/Loop.
- Audio follows mute; fall back to the still when motion is missing or corrupt.

### Stills

- Keep the Immich preview as fallback while adding libheif/LibRaw.
- Preview-first, isolate decode, display-size + pan-headroom derived cache.

### Slideshow integration

- Replace the video/Live Photo placeholders.
- Player lifecycle around slide changes, including `AnimatedSwitcher` and rapid next/previous.
- Preserve the current image-fit rules and transitions.

### Cache

- Add video originals, Live Photo motion, and derived stills to the existing
  cache/download/sync/prefetch/eviction/clear/stats paths.
- Include DB/schema migration and cleanup.

### HDR and fallbacks

- Tone-map HDR to SDR for video and stills.
- Codec failure → Immich playback stream or skip with log.
- Missing/corrupt motion → still.
- `asset.download` denied → videos unavailable; corrupt files never crash.

## Out of scope

- `speedUp`/`highlights`/`slice` video modes.
- Per-aspect Live Photo mode; v1 keeps the global setting (deviation from AP-01 to be recorded) unless
  a migration is required.
- Plugins.
- Start-on-boot/kiosk/updates.
- True HDR output, HDR10+ dynamic metadata, and Dolby Vision.
- Other camera RAW formats beyond DNG/ProRAW; TIFF and other unlisted still formats.
- Background audio playback.

## Tasks

1. Add and pin media_kit/libmpv, libheif/LibRaw FFI, and native build scripts for
   Windows/Linux/Android.
2. Extend cache model/database/downloader/sync/prefetch/eviction/clear/stats for video originals,
   Live Photo motion, and derived stills.
3. Implement the player abstraction and media_kit adapter (local-first, Immich original URL with auth
   headers, hardware/software decode, one active player, event mapping, dispose on slide change).
4. Integrate video playback with the slideshow (replace placeholders, `full` mode, per-asset
   duration/auto-advance, pause/resume/next/previous/progress, preserve transitions/fit).
5. Enable audio/mute and Android audio focus; Live Photo audio follows the same mute state.
6. Implement Live Photo motion resolution and global Off/Live/Loop behavior with still fallback.
7. Add libheif/LibRaw decode, preview-first, isolate/worker decode, display-sized sRGB 8-bit derived
   cache, and cache invalidation.
8. Configure and verify HDR-to-SDR tone-mapping for video and stills.
9. Implement fallbacks/diagnostics (permission denial, missing motion, corrupt/truncated files, cache
   miss/network failure, storage pressure).
10. Add fixtures/tests/performance measurements (regenerate fixtures removed with the spike;
    player-leak and memory checks; keep the existing 182 tests green).
11. Update docs and platform limitations.

## Deliverables

- Video playback with audio, lifecycle, and auto-advance.
- Live Photo Off/Live/Loop playback with still fallback.
- HEIC/AVIF/DNG/ProRAW still support with display-sized derived cache.
- Extended cache schema/migration covering video, motion, and derived stills.
- HDR tone-mapping configuration and evidence.
- Fallback handling, diagnostics, and tests.
- Updated media/platform docs.

## Acceptance criteria

- [ ] H.264 video plays with audio; mute/pause/resume/next/previous work.
- [ ] `off` and `staticPreview` remain unchanged; `full` works; `speedUp`/`highlights`/`slice` stay
      disabled.
- [ ] The existing `muted` setting is effective; no background playback.
- [ ] HEVC 10-bit HDR and HLG video play tone-mapped to SDR.
- [ ] AV1/VP9/ProRes files play or fall back gracefully (recorded per platform).
- [ ] Live Photo Off/Live/Loop behaviours match the spec; audio respects mute.
- [ ] Live Photo modes use the global setting; missing/corrupt motion falls back to the still.
- [ ] HEIC/AVIF/DNG/ProRAW display correctly with acceptable time/memory.
- [ ] Unknown/unsupported stills fall back to Immich previews.
- [ ] Corrupt/truncated media never crashes the slideshow.
- [ ] Current fit rule is preserved (fit authoritative; pan/motion only with Cover).
- [ ] Per-aspect fit applies to videos; profiled pan rules remain correct.
- [ ] Cache migration preserves the existing photo cache; video originals, motion, and derived bytes
      are counted/evicted; no player/media-handle leaks.
- [ ] `asset.download` denied means videos are unavailable/skipped.
- [ ] Existing 182 tests remain green.
- [ ] No player/media-handle leaks over repeated slide changes.
- [ ] HDR limitation is documented and no HDR output is claimed.
- [ ] CI green; docs updated.

## Risks

| Risk | Mitigation |
|---|---|
| Cache schema migration and stale derived/motion files | Versioned migration preserving photo cache; invalidate derived data on checksum/profile change; test upgrade path |
| Player lifecycle vs `AnimatedSwitcher` and rapid next/previous | One active player; explicit dispose on slide change; serialise transitions; leak test |
| Native build/licensing complexity for libmpv/libheif/LibRaw | Pin sources/versions; per-platform build scripts; document licensing/build options |
| HEVC 10-bit Android decoder blocker | Pin/build libmpv with HEVC or use the Immich playback stream; record in diagnostics; test on the reference device |
| Global Live Photo mode vs REQUIREMENTS AP-01 per-aspect wording | Keep global v1 and record the deviation; add a settings migration only if per-aspect is required |
| ProRAW render quality differs from Apple | Embedded preview fallback; document |
| libmpv build missing a codec | Pin build; test matrix; Immich fallback |
| Android hardware decode variance | Test low/high-end; software fallback |
| RAW decode memory spikes | Preview-first, background decode, screen-sized cache, budget |
| HDR tone-map looks flat | Tune mpv tone-mapping/target peak; visual acceptance |
| Audio focus conflicts | Explicit focus handling and tests |
| Cache growth from video/motion | Extend quota/eviction/stats to new categories |

## Delivery log

| Date | Result | Notes |
|---|---|---|
| 2026-10-29 | Plan revised | Aligned with delivered Phase 2 and cleanup: settings schema v2, photo-only cache, preview placeholders, removed offline resolver/Result, 182 tests. |
| 2026-10-29 | Cache plumbing | Video originals, Live Photo motion, derived/motion paths, DB v3 migration, eviction/stats; 189 tests passing. |
| 2026-10-29 | Playback layer | media_kit 1.2.6/media_kit_video 2.0.1, MediaPlayback/MediaKitPlayback, main initialization; 193 tests passing. |
| 2026-10-29 | Video slideshow | Full video mode, per-slide duration/auto-advance, mute control, settings enablement; 204 tests passing. |
| 2026-10-30 | Live Photo playback | Off/Live/Loop motion, still fallback, settings enabled; 211 tests passing. |
| 2026-10-30 | Still pipeline | Decoder seam, derived JPEG cache, display precedence, one-at-a-time derivation, isolate decode; 225 tests passing. |
| 2026-10-30 | Native stills | libheif/LibRaw FFI, provider selection, Windows native HEIC/AVIF verified, LibRaw verified with a real Pentax DNG; 236 tests (2 native skips without DLLs). |
| 2026-10-30 | Native builds | Windows build script verified locally; Linux/Android scripts added but unverified; CMake bundling and CI cache wired. |
| 2026-10-30 | HDR config | media_kit SDR tone-mapping defaults added; visual HDR verification still pending. |
