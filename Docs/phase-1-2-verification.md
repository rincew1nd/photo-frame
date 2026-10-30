# Phase 1 and Phase 2 Verification

Status: Automated/API verification complete; platform-runtime verification partial
Date: 2026-10-27
Related: [`../Plans/phase-1-foundation.md`](../Plans/phase-1-foundation.md),
[`../Plans/phase-2-photos-cache.md`](../Plans/phase-2-photos-cache.md)

## 1. Environment

| Item | Value |
|---|---|
| Flutter / Dart | 3.47.8 / 3.13.7 stable |
| Windows | Windows 11 25H2, x64, Visual Studio Build Tools 17.14 |
| Android | Huawei AGS3K-W09, Android 10 / API 29, arm64; device disconnected during final verification |
| App identity | `com.rincew1nd.photoframe`, version 1.0.0+1, minSdk 26 |
| Immich | 3.3.5 (read-only access to the supplied test server) |
| Linux | No Linux host available; CI workflow configured but not executed |

The supplied Immich API token is not stored in the repository, documentation, logs, or test fixtures.
Real-server checks used it only through environment variables in throwaway test files.

## 2. Commands and results

```text
flutter analyze                         -> No issues found
flutter test                            -> the full test suite passes
flutter build windows --debug           -> built build/windows/x64/runner/Debug/photoframe.exe
flutter build apk --debug               -> built build/app/outputs/flutter-apk/app-debug.apk
```

The tests cover:

- settings defaults, JSON round-trip, migrations, corrupt-file fallback, and atomic saves;
- log redaction for API keys, authorization headers, bearer values, and registered secrets;
- secure-store abstraction;
- Immich URL normalization, API-key/bearer headers, DTO parsing, paging, error mapping;
- the five-permission report, including `asset.download` degradation and empty libraries;
- PKCE generation and OAuth begin/finish/API-key creation against a mock Immich v3 server;
- API-key and OAuth persistence, disconnect, and recheck;
- connection controller success/failure/refresh/album-selection persistence;
- setup, albums, settings groups, connection UI, slideshow, media selection, and no-items states;
- media type/aspect filters, unknown dimensions, per-aspect profiles, pan/cover rules;
- aspect boundaries (1.15/1.42/1.64/2.0) and orientation-neutral classification;
- slideshow sequencing, shuffle, wrap, pause/tick, progress, and empty state;
- cache store CRUD/stats, downloader atomic writes, retries, SHA-1 checksum verification, Range resume;
- sync, prefetch, and LRU eviction with current/next protection;
- weather parsing/cache/failure behavior and night-mode windows.

Separately, an accelerated 24-hour-equivalent slideshow soak was run; the throwaway soak driver was
not kept in the repository.

## 3. Real Immich checks

Read-only checks against Immich 3.3.5:

- `GET /api/server/version` -> 3.3.5.
- `GET /api/users/me` -> authenticated user.
- `GET /api/albums` -> 23 albums.
- `POST /api/search/metadata` (album `Tests`, page 1) -> 8 assets.
- The five required permissions were all reported granted:
  `user.read`, `album.read`, `asset.read`, `asset.view`, `asset.download`.
- Thumbnail download returned `image/webp`; original download supported a `Range` request.
- A real cache sync of the 8-asset album downloaded 8 assets / 28,525,706 bytes with zero failures.
  A second sync downloaded 0 and skipped 8, proving the checksum/skip path.
- The asset metadata provided EXIF width/height, MIME type, checksum, and Live Photo ids; the
  aspect resolver classified a 1920x1080 video as 16:9.

The production setup UI on the Android API 29 reference connected to the real server with the API key
path and displayed all five permissions as granted (see `Docs/evidence/android-connected.png`). The
API key field is cleared after a successful connection. The device disconnected again after this
check, so the manual albums/slideshow pass was not completed.

The supplied server's HTTP URL returns a 308 redirect to HTTPS. The client accepts both schemes;
users should enter `https://` when the server redirects (the setup UI also surfaces the 308 hint).

## 4. Runtime issues fixed after the first device pass

- Settings screens now have explicit Back/Done navigation to albums; the connection screen returns to settings, and media selection returns to the slideshow. GoRouter `go()` previously replaced the stack, leaving no back target.
- The slideshow now uses thumbnails for original formats Flutter cannot decode (HEIC/AVIF/RAW) and falls back from a failed original decode to the thumbnail, so "Could not decompress image" no longer drops the slide.
- Video assets show an explicit "Video playback arrives in Phase 3" state instead of a low-quality thumbnail presented as playback. Live Photo motion shows a Phase 3 hint when live/loop is selected; both remain Phase 3 scope as planned.
- Images are wrapped in viewport-filling constraints so `BoxFit.contain/cover` actually applies; the slideshow no longer renders intrinsic-size thumbnails.
- Cached display images now use Immich `preview`-sized JPEG/WebP instead of tiny thumbnails, and HEIC/AVIF/RAW originals never fall back to an undecodable file. The controller auto-syncs when previews are missing, with an explicit Sync control.
- Settings saves are now written synchronously once the support path is known, the controller updates state immediately, and leaving settings waits for the pending write. New file-backed tests prove an unawaited save is on disk immediately and survives a simulated restart.
- Ken Burns panning uses the image's actual cover overflow: at 100% the full image edge-to-edge range is traversed during one slide interval; wide images pan horizontally, tall images vertically, and near-viewport aspect ratios zoom in/out. Animation duration is tied to the slide interval. The panned image box is sized to the full cover image, not the viewport, so translation cannot expose black bars.
- The full test suite passes, including these fixes.

## 5. Platform notes and gaps

1. **Android runtime:** setup and real-server connection were manually verified on the API 29
   reference (five permissions granted). The device disconnected again before the albums/slideshow
   acceptance pass, so cached playback, filters, night mode, and overlays were not manually driven on
   Android. The Phase 0 spike established H.264/AV1 playback and the WebView limitations recorded in
   `spike-0-results.md`.
2. **Linux:** no Linux host was available. The CI workflow installs Flutter, GTK, ninja, libsecret,
   and libjsoncpp and runs `flutter build linux --debug`; CI has not been executed in this session.
3. **Windows secure storage:** the Windows build tools on this host lack ATL, which
   `flutter_secure_storage_windows` 4.2.2's native plugin requires. The repository vendors the
   package with its Dart FFI Windows implementation and removes the native plugin entry
   (`third_party/flutter_secure_storage_windows`). This uses Windows Credential Manager through the
   package's Dart implementation and avoids the ATL dependency. CI Windows runners with ATL should
   also build, but the vendored path is the verified local configuration.
4. **OAuth end-to-end:** PKCE, loopback/Android callback orchestration, token exchange, and API-key
   creation are tested against the mock server. A real OAuth provider round trip was not performed.
5. **Soak:** the accelerated soak covers 8,640 slide changes (24 hours at a 10-second interval) with
   image decode/dispose in 5 seconds and ~12.5 MB RSS growth (limit 128 MB). A 24-hour wall-clock
   device soak and file-handle sampling were not run.
6. **Manual UI:** the Windows setup screen was launched and captured; full manual setup, album
   selection, cached slideshow, night mode, and overlay interaction were not driven on a device.
7. **CI:** workflow definitions exist for analyze/test, Android, Windows, and Linux, but no GitHub
   Actions run is available in this environment.

## 6. Evidence

- `Docs/evidence/windows-setup.png` — Windows setup screen launch.
- `Docs/evidence/android-setup.png` — Android setup screen.
- Accelerated soak — result recorded in section 5; the throwaway driver was not kept.
- `test/support/mock_immich_server.dart` — mock Immich v3 server used by the suite.
- `test/data/immich/*` — API, OAuth, permissions, auth-service tests.
- `test/data/cache/*` — cache, downloader, sync, eviction tests.
- `test/domain/*`, `test/features/*` — filters, profiles, slideshow, settings, UI tests.
