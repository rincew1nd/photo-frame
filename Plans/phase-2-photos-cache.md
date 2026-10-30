# Phase 2 — Photos, Cache, Filters, and Settings

Status: Done (automated verification; 24h wall-clock soak and manual platform pass partial)
Depends on: Phase 1
Unblocks: Phase 3, Phase 4

## Goal

Deliver a photo-only slideshow that works offline, respects media/aspect filters and per-aspect
profiles, and exposes the full settings experience required by SET-01..SET-09.

## Scope

### Slideshow

- Full-screen photo slideshow with configurable interval, shuffle, and transition.
- Manual previous/next, pause/resume.
- Progress indicator.
- No-items state when filters exclude everything.
- Ken Burns pan/zoom with per-aspect fit and pan strength.
- Unknown/missing dimensions always shown with the Default profile.

### Cache and offline

- Album sync: fetch metadata, reconcile, download originals and thumbnails.
- Live Photo motion files can be cached later; photo cache only in this phase.
- Atomic downloads, checksums, retry/backoff, resume.
- Prefetch next N slides.
- LRU quota/eviction with current/next protection.
- Offline resolution and no-items state.
- Cache statistics and sync controls in settings.
- Persistence across restart/process death.

### Filters and profiles

- Type filter (Photos/Live Photos/Videos; video types shown but not playable until Phase 3).
- Aspect filter with at least-one-selection guard.
- Aspect classification and orientation-neutral buckets.
- Default profile and five bucket overrides.
- Per-aspect fit, Live Photo mode (stored; exercised in Phase 3), pan strength.
- Seeding from Default and persistence.
- Effective profile resolution per asset.

### Settings and overlays

- Complete settings groups:
  - Playback
  - Media Filters & Aspect
  - Display
  - Overlays & Plugins (built-in overlay controls only)
  - Automation (placeholders)
  - Media Cache
  - Connection & Security
  - About & Diagnostics
- Summaries, expand/collapse, persistence.
- Night mode: schedule, overnight windows, dimming, paused slideshow, hidden overlays.
- Built-in clock, weather, and photo-metadata overlays (independently toggleable).
- Media selection grid with thumbnails, manual selection, filter-aware counter, biometric gate.
- Onboarding tour targets.

### Presentation

- Photo transitions and adaptive background/letterbox treatment from the existing design.
- Safe-area/inset handling on Android.
- Basic diagnostics/log viewer.
- Localization for the defined v1 locale set (English minimum).

## Out of scope

- Video/audio/Live Photo playback.
- HEIC/AVIF/DNG/ProRAW decoding beyond Flutter’s built-in formats.
- Plugins.
- Start-on-boot, kiosk, biometric integration (except the media-selection gate placeholder).
- Update checks.

## Tasks

1. Implement slideshow engine and sequence building.
2. Implement photo rendering, fit/cover, transitions, pan/zoom.
3. Implement cache DB, downloader, sync, prefetch, eviction, offline resolver.
4. Implement filters, aspect classification, profiles, and persistence.
5. Build media selection with biometric gate and counter.
6. Build complete settings groups and summaries.
7. Implement night mode.
8. Implement built-in clock/weather/metadata overlays.
9. Add no-items/error/offline states.
10. Add unit/widget/integration tests and a 24-hour photo soak.
11. Update docs and acceptance evidence.

## Deliverables

- Offline-capable photo slideshow.
- Cache/sync/eviction implementation.
- Complete settings UI for filters/profiles/cache/night mode.
- Media selection and built-in overlays.
- Tests and measurement results.
- Updated documentation.

## Acceptance criteria

- [x] Photos play from cache with the server offline. (Cache/UI paths tested; manual device pass pending.)
- [x] Type/aspect filters apply without restart; at least one remains selected.
- [x] Unknown dimensions are never filtered out and use Default.
- [x] 16:9 Cover, 4:3 Contain, Panorama Contain/pan 0 render as configured.
- [x] Pan > 0 forces Cover; pan 0 honours fit.
- [x] Filters/profiles/settings survive restart.
- [x] No-items state is shown instead of a black frame.
- [x] Media counter reflects filtered assets while the grid still lists all.
- [x] Night mode handles overnight windows and pauses the slideshow.
- [x] Built-in clock/weather/metadata overlays toggle independently.
- [ ] 24-hour photo soak shows no unbounded memory/file-handle growth. (Accelerated 24h-equivalent soak passed; wall-clock device soak pending.)
- [ ] CI green; docs updated. (Docs updated; CI not run.)

## Risks

| Risk | Mitigation |
|---|---|
| Large cache on Android | Quota, eviction, storage diagnostics |
| EXIF dimensions missing/inconsistent | Unknown-dimension rule; Default profile |
| Night-mode dimming on desktop | Overlay dimming; document lack of panel brightness |
| Cache/sync races with slideshow | Domain resolver and DB transactions; tests |
| Weather provider/legal terms | Provider abstraction; disable by default until configured |

## Delivery log

| Date | Result | Notes |
|---|---|---|
| - | - | - |
| 2026-10-27 | Done (verification partial) | Photo slideshow with cache/offline resolver, sync/prefetch/LRU eviction, type/aspect filters, per-aspect profiles, grouped settings, night mode, built-in clock/weather/metadata overlays, media selection/biometric gate, diagnostics, and accelerated soak. Real cache sync of the 8-asset `Tests` album downloaded 8 assets (28,525,706 bytes) with zero failures and re-synced with zero downloads. Accelerated 24h-equivalent soak: 8,640 slide iterations, ~12.5 MB RSS growth. 24h wall-clock soak and manual Windows/Android slideshow pass remain; see `Docs/phase-1-2-verification.md`. |
