# Data, Authentication, Cache, and Settings

Status: Draft v0.1
Related: [`architecture.md`](architecture.md), [`media.md`](media.md), [`security.md`](security.md)

## 1. Immich API

The app talks directly to an Immich server. No intermediary service is deployed.

### Required capabilities

- Server URL validation and connectivity check.
- API key entry, API key generation after login, and OAuth PKCE.
- Permission verification and degradation.
- Album listing and multi-selection.
- Asset listing with pagination, thumbnails, EXIF, tags, dimensions, MIME type, and Live Photo
  relationships.
- Original download and optional playback stream.
- GitHub release metadata for app updates.
- Weather data for the built-in overlay and plugin snapshot (Open-Meteo or equivalent, no auth).

### Authentication

- API key input creates the primary session and is stored in platform secure storage.
- OAuth PKCE:
  - Android: system browser/Custom Tabs, redirect to the app’s custom scheme.
  - Desktop: system browser with a loopback redirect.
- The app logs out and clears tokens through the Connection & Security settings.
- The API key is sent via `x-api-key` headers for API calls and media requests.
- Never place the API key in URLs, logs, screenshots, plugin data, or crash reports.
- Permission probes use the same auth path as the feature they validate:
  - API calls: header auth.
  - Media: the same header path used by the media pipeline.

### Required permissions

The five required permissions from BR-02 are checked after connecting:

- `user.read`
- `album.read`
- `asset.read`
- `asset.view`
- `asset.download`

Blocking permissions prevent setup completion. Missing `asset.download` degrades videos and
explains the limitation. Live Photos remain available. Permission results are persisted and
re-checked on startup/connection changes.

## 2. Albums and asset model

- Albums are fetched with paging; selection is persisted.
- Assets include:
  - id, album ids, type (image/video), Live Photo flag/video id;
  - original MIME type, dimensions, duration;
  - EXIF date, description, city/state/country, tags;
  - thumbnail URL, original URL, checksum/modified time;
  - aspect bucket and filter eligibility.
- Animated GIFs are classified as Photos; Live Photos are classified as Live Photos.
- Manual media selection, type filters, and aspect filters combine with AND semantics.
- Assets with missing/invalid dimensions are always shown and use the Default profile.

## 3. Cache

### Goals

- Offline-capable slideshow.
- Instant slide changes once synced.
- Bounded disk usage.
- Correct recovery from interrupted downloads and corrupt files.

### File layout

```
<app support>/cache/
  originals/<album-id>/<asset-id>.<ext>
  thumbnails/<asset-id>.jpg
  live/<asset-id>.mov            # motion video for a Live Photo
  derived/<asset-id>.<ext>       # display-sized HEIC/RAW conversions
  temp/                           # atomic download staging
```

Paths are stored relative to the cache root so the app can move its support directory between
platform builds.

### Database

Drift/SQLite tables:

| Table | Purpose |
|---|---|
| `cached_assets` | Asset id, album id, type, local paths, size, checksum, last modified, cached at, MIME, EXIF, tags, aspect, duration, Live Photo video id |
| `album_sync_states` | Album id, last sync, cursor/page state, asset count |
| `derived_images` | Derived path, source checksum, decode profile, dimensions |
| `plugin_registry` | Installed plugin id, version, bundle path, enabled state, API version |
| `plugin_instances` | Instance id, placement, z-order, visibility, config JSON, night-mode flag |
| `plugin_storage` | Namespaced key/value storage per plugin instance |
| `schema_meta` | Applied cache database schema version |

The cache database is disposable: a destructive reset may be used for cache tables, but plugin
configuration and settings must survive unless the user uninstalls the plugin/changes the setting.

### Sync lifecycle

1. On slideshow load, resolve cached assets for selected albums.
2. Start or resume an album sync:
   - fetch asset metadata with paging;
   - reconcile additions/changes/deletions;
   - download originals, thumbnails, and Live Photo motion;
   - write atomically (temp file + rename);
   - verify checksum where available;
   - update DB rows.
3. Prefetch the next N slides (default 3; configurable).
4. Continue syncing in the background while the app runs.
5. On network failure, keep the existing cache and retry with backoff.
6. On app restart, resume from persisted sync state; do not re-download valid files.

Concurrency is bounded (downloads and decodes). The current slide is never evicted.

### Offline resolution

- Media resolver checks local original first.
- Missing local file → network original with headers.
- Network unavailable → cached media only; if nothing matches, show the no-items state.
- Video/Live Photo motion falls back to cached still if motion is unavailable.

### Eviction

- Configurable cache quota (defaults proposed: 10 GB desktop, 4 GB Android; user-adjustable).
- LRU by last access, excluding:
  - the current slide;
  - the next prefetched slides;
  - pinned/protected items if pinning is added later.
- Evict derived images before originals.
- Eviction runs after sync and on storage pressure.
- A cache statistics/diagnostics screen shows size, counts, and last sync.

### Storage and permissions

- Android: app-private storage; no broad storage permission.
- Windows/Linux: app support directory; no writes outside it except exports/log sharing.
- Writes use temp files and atomic rename.
- The cache is not encrypted; it contains user photos. OS disk encryption is the protection boundary.
  The API key is separate and encrypted in secure storage.

## 4. Settings

### Repository

- Typed settings model with schema version and migrations.
- Persisted atomically (JSON file or platform preferences, behind one repository interface).
- All changes update the running app without restart.
- Secrets are not stored in the settings file.

### Settings areas

- Playback: interval, shuffle, transition, mute, video/Live Photo type filter, aspect filter.
- Media Filters & Aspect: Default profile and five buckets (fit, Live Photo mode, pan strength).
- Display: keep screen on, night mode window/brightness, theme, image motion.
- Overlays & Plugins: built-in overlays, plugin management, permissions, placement, settings.
- Automation: start on boot, launcher mode (Android), kiosk/fullscreen (desktop), update checks.
- Media Cache: quota, prefetch count, sync now, cache statistics.
- Connection & Security: server, API key/auth, permissions, biometric gating, logout.
- About & Diagnostics: version, plugin API version, logs, crash reports, licenses, server status.

Groups are collapsible; expanded state persists for the session/device; the first group opens by
default. The onboarding tour can deep-link to a group.

### Migrations

- Settings schema is versioned.
- New settings have defaults.
- Plugin config migrations follow the plugin settings schema; incompatible updates require
  confirmation.
- MR-04’s legacy upgrade mapping is removed for this new application (fresh install defaults).

## 5. Plugin data

- Plugin bundles live under `<app support>/plugins/<id>/<version>/`.
- The registry stores identity, version, API version, bundle path, enabled state, and checksum.
- Instance configuration and placement live in the app DB.
- Plugin storage is namespaced by instance and removed on uninstall.
- Screenshots and descriptions come from the installed bundle and are displayed in the install UI.

## 6. Weather

- The app fetches weather for the built-in overlay when configured.
- Weather data is exposed to plugins through the snapshot only when enabled and available.
- Failures return null to plugins; they do not block slideshow playback.
- Location can be configured manually or derived from EXIF/device location with permission. The
  exact provider and location strategy are implemented in Phase 2/3.

## 7. Background operation

- The app is expected to run continuously as the visible frame.
- In-app sync and prefetch run while the slideshow is active.
- Android background sync via WorkManager is optional and only needed when the app is not visible.
- No background media playback in v1.

## 8. Error handling

| Situation | Behaviour |
|---|---|
| Server unreachable | Use cache; show offline/status indicator; retry with backoff |
| Auth revoked/401 | Stop sync; prompt for reconnect; keep cached slideshow |
| Permission missing | Degrade features; block setup only on blocking permissions |
| Album deleted | Remove its cached assets subject to retention; show no-items if nothing remains |
| Disk full | Stop prefetch; keep current; diagnostics message |
| Checksum mismatch | Delete file; re-download |
| Malformed metadata | Keep asset but skip/fallback at display time |
| Settings migration failure | Back up, reset affected settings, log; do not lose API key |

## 9. Testing

- Immich client contract tests with fixtures.
- Permission degradation tests.
- Cache download/resume/eviction/offline tests.
- Settings migration tests.
- Plugin registry/storage lifecycle tests.
- Restart/process-death persistence tests.
- Server-down, auth-revoked, album-deleted scenarios.
