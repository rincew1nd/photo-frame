# Phase 4 — Plugin System

Status: Done (M1–M7 implemented; Windows and Android runtime verified; 72-hour video/frame-drop soak remains a Phase 6 release gate)
Depends on: Phase 1 (done), Phase 3 (core media implemented; verification gaps remain), Phase 0
overlay/WebView validation
Unblocks: Phase 5 plugin/WebView items and Phase 6

Baseline at revision: `d996627` plus the uncommitted Phase 5 platform work. `flutter analyze` is
clean and the existing unit/widget suite passes (2 native skips without DLLs). Windows default and
kiosk launches and Android split release APKs were verified; Linux has no runtime validation.

## Starting point (current state, 2026-11-01)

### Reusable prerequisites

- Phases 1–2 are done and Phase 3 core media playback is implemented. The slideshow is a Flutter
  `Stack` with a photo/video layer, compiled clock/weather/metadata overlays inside `SafeArea`,
  night dimming, and app controls. The plugin layer belongs between the media and controls layers.
  The compiled overlays are the migration source; the v1 target is for them to become bundled
  plugins so no compiled-in overlay remains.
- `SlideshowController`/`SlideshowViewState` already expose most snapshot inputs: current asset,
  index, total, playing, progress, cached assets, weather, night mode, and per-asset EXIF. A
  redacted snapshot builder is still required; pass the reduced snapshot, never `ImmichAsset`,
  `CachedAsset`, file paths, or credentials.
- `CachedAsset` already carries description, location, and a tags list. Tags are currently always
  empty because `MediaDownloader.ensureAsset` sets `tags: const <String>[]`; PLG-22 tag support needs
  a sync change or an explicit requirement amendment.
- Weather is available through `WeatherService`, but `SlideshowController` only fetches it when the
  compiled weather overlay is enabled and coordinates are set. Once weather is a plugin, the host
  must fetch it for any plugin that declares the weather input, using the weather plugin's settings,
  independent of the old compiled overlay toggle.
- Settings are schema v3 and persisted atomically as `settings.json`; `SettingsRepository.migrate`
  is the migration point. There is no plugin configuration, placement, or registry section yet.
  `AppSettings.toJson` drops unknown fields, so plugin state must be modeled before persisting it.
- The Drift `AppDatabase` is schema v3 with only `cached_assets`, `album_sync_states`, and
  `schema_meta`. There is no plugin registry or plugin storage table; add them with a migration or
  use a file-backed store.
- `OverlaySettings` already holds the compiled clock/weather/metadata switches and weather
  coordinates. These fields are the migration source for the bundled example plugins; they must not remain
  as a second control path. The `/settings/plugins` route and the Plugins summary exist, but the UI
  is a placeholder (`0 plugins`, disabled **Add plugin**).
- Loopback socket code exists only for desktop single-instance focus signalling
  (`FileLockSingleInstance`); it is not an HTTP server and must not be reused as the plugin host.
  `AppLogger` is available for plugin error attribution.
- `SafeArea` is used for the compiled overlays and controls, so the plugin placement clamp can reuse
  the same insets. Android minimum is API 26.

### Not present

- No plugin code, manifest model (icon/inputs), ZIP validation, registry, install UI, per-plugin
  settings screen, host page, bridge, snapshot, sandbox, CSP/request interception, placement editor,
  drag/resize/grid snapping, plugin storage, or bundled example plugins.
- No `webview_cef`, `webview_flutter`, ZIP/archive, or local HTTP-server dependency in
  `pubspec.yaml`; no desktop CEF bundle or runner hooks.
- No app lifecycle observer. Plugin tick pause on background/screen-off must be added; the current
  app only reacts to slideshow visibility and night mode.
- About & diagnostics shows a hardcoded `Plugin API v1` and no CEF/WebView version.
- No plugin install, security, or performance tests. Existing tests cover Phase 1–3 only.

### Inherited gates

- Phase 0 is a conditional no-go for transparent overlays. `webview_cef` 0.6.2 exposes no
  transparency/background API; the available Android reference WebView (12.1.2.326) is below the
  Chromium 100+ baseline and rendered plugin HTML blank. Windows CEF transparency/input was not
  runtime-verified, and Linux was never run.
- Phase 0 requires resolving CEF transparency (patch CEF/OSR or use an alternative) and validating
  a modern Android WebView before production plugin work. Because all overlays become plugins, below
  the baseline the slideshow runs without overlays; this is a product trade-off to confirm before
  removing the compiled overlays.
- Phase 3 is still `In progress` for HDR tuning and Linux/Android native library verification, but
  the media layering the plugin host depends on is present.

## Goal

Deliver the complete plugin lifecycle and rendering host: local ZIP install/update, transparent
interactive overlays, sandboxing, host-mediated network/storage/actions, per-plugin settings,
drag/resize/grid placement, and bundled example plugins that replace the current compiled
clock/weather/metadata overlays.

## Scope

### Bundle and manifest

- ZIP layout with `plugin.json`, entry HTML, CSS, optional JS/assets, optional screenshots and icon.
- Manifest schema: id, name, version, apiVersion, minAppVersion, author, homepage, license,
  description, entry, icon, screenshots, permissions, inputs, actions, updateTriggers, placement,
  settings.
- Validation: schema, traversal, bombs, limits, duplicate IDs, API compatibility, entry, icon and
  screenshot types/sizes, declared inputs.
- SHA-256 recorded.

### Lifecycle and UI

- Install from local ZIP.
- Install/details UI: identity, icon, description, screenshots, permissions, requested inputs,
  compatibility, license.
- Enable/disable, update, uninstall, inspect.
- Plugin list with icon; each installed plugin opens its own settings screen (Plugins → plugin).
- Per-plugin settings screen renders the manifest schema, lifecycle controls, and placement editor.
- Update preserves compatible config; incompatible schema requires confirmation.
- Uninstall removes bundles/config/storage.
- Placement editor: direct drag/resize over the slideshow (edit mode) and from the plugin settings
  screen, optional grid snap and grid size; per-instance visibility/night-mode option.
- Migrate compiled clock/weather/metadata state into bundled example plugins; remove the compiled overlay
  toggles after migration.

### Host and rendering

- Per-instance transparent webview:
  - CEF/`webview_cef` on Windows/Linux;
  - system WebView/`webview_flutter` on Android.
- Loopback server with ephemeral port/token; host page and plugin assets.
- Sandboxed iframe; opaque origin; CSP; no host storage/cookies.
- Host-owned placement: default, plugin request, drag/resize, grid snap, clamp to safe area,
  animate, persist.
- Click-through outside the plugin box.
- App controls/dialogs above; Android hide-overlay fallback if required.
- Input: buttons, links, text where supported; IME; drag handles in the placement editor.
- External links intercepted/opened in system browser with confirmation; blocked schemes/popups.

### Bridge and API v1

- State snapshot (app/time/weather/playback/image/config/placement), filtered to the manifest's
  declared `inputs` plus mandatory app/time data.
- 1 Hz ticks; immediate events; coalescing; pause when hidden/background/screen off.
- `host.requestPlacement`, `host.action`, `host.openLink`, storage, network proxy, logging/errors.
- Settings schema rendering/validation in Flutter; read-only config to plugin.
- Actions: next/previous/pause/resume/mute/open settings/open media selection; declared/granted/
  rate-limited.
- Network permission: denied by default; host proxy; no direct fetch; no credentials.
- Plugin storage namespaced, limited, removed on uninstall.
- Failure isolation: load timeout, repeated-failure disable, watchdog, hidden when failed.
- WebView baseline check/degradation on Android.

### Bundled example plugins

- Clock/time, calendar/date, weather, playback status, image info.
- Seeded on first run and use the same ZIP, manifest, registry, settings, and host path as any
  third-party plugin; no special-case code path.
- Clock/weather/metadata start enabled; other examples start disabled. After seeding they are
  ordinary plugins: disable or uninstall/delete any of them; deletion is not undone automatically.
- Icons, descriptions/screenshots; settings/time-tick/image-change demos; weather plugin owns the
  location/unit/label settings.
- No compiled-in overlays remain.

## Out of scope

- Marketplace, remote install, signatures, multiple instances per plugin.
- Plugins outside the slideshow.
- Plugin access to Immich/library/credentials.
- Native code plugins/background services.
- App-provided calendar feeds.
- Remote asset allowlists (future).

## Implementation plan (2026-11-01)

### Sequencing rules

- **The Windows M0 gate gates host code.** The software pixel-buffer path is proven; Android runtime
  validation must pass before release. M1 package and persistence work may proceed in parallel
  because it is independent of rendering.
- **Do not remove compiled overlays until M6.** Keep the current overlays working through M1–M5.
- Keep plugin API v1; no marketplace, signatures, or multiple instances.
- Reuse existing dependencies (`dio`, `crypto`, `path`, `path_provider`, `drift`, `url_launcher`,
  `package_info_plus`). Add only `archive` for ZIPs, `webview_flutter` for Android, and
  `webview_cef` for desktop. Use `dart:io HttpServer` for the loopback server; no server package.

### Suggested file layout

```
lib/features/plugins/     plugin list, install/details, per-plugin settings, placement editor
lib/data/plugins/         manifest, bundle validation, store, registry, storage, migration
lib/domain/plugins/       snapshot builder, placement model
lib/plugins/host/         loopback server, host page, bridge, adapters, watchdog
plugins/examples/         bundled example plugin sources
plugins/zips/             packaged example ZIPs loaded by the app
test/...                  unit/widget/integration/security/performance/migration tests
```

### Milestones

#### M0 — Prove the overlay gate (blocking)

- Follow up Phase 0: patch CEF/OSR transparency or evaluate an alternative.
- Verify on Windows: alpha, input, click-through, Flutter controls above, move/resize, 1 Hz updates,
  no obvious leaks.
- Verify on a Chromium 100+ Android device/emulator: transparency, input, IME, z-order or the
  hide-webviews fallback.
- Run Linux if a host is available; otherwise record it as unverified.
- Record evidence and pinned CEF/WebView versions.

**Exit:** go/no-go recorded. No-go stops Phase 4 and keeps the compiled overlays.

#### M1 — Package, validation, and persistence (parallel with M0)

- Add `archive`; implement manifest parsing and validation for identity, compatibility, permissions,
  inputs, actions, icon, screenshots, settings schema, and placement.
- Implement ZIP validation: traversal, symlinks/devices, bombs, size/file limits, entry presence,
  icon/screenshot types, duplicate IDs, SHA-256.
- Add DB schema v4 tables: `plugin_registry`, `plugin_instances`, `plugin_storage`; add migration.
- Implement plugin store/registry/config/storage lifecycle, quotas, and atomic update/uninstall.
- Add settings v4 placement grid fields (snap enabled, grid size) and a seed/migration marker.
- Seed bundled example ZIPs from `plugins/zips/` through the normal install path.

**Exit:** unit tests for manifests, ZIPs, registry/storage, and DB migration; no UI rendering yet.

#### M2 — Host transport and sandbox

- Build the loopback server, host page, per-instance token/path serving, CSP, and shutdown.
- Add Android `webview_flutter` and desktop `webview_cef` adapters with transparency, sizing,
  disposal, load timeout, and diagnostics version reporting.
- Implement the sandboxed iframe, request interception, click-through outside the box, controls
  above, and the Android hide-webviews fallback if required.

**Exit:** one plugin renders transparently and interactively on Windows and a modern Android
WebView; clicks outside pass through; Flutter controls stay above.

#### M3 — Bridge, state, capabilities, failure isolation

- Build the versioned `postMessage` bridge and snapshot builder filtered by `inputs` (never pass raw
  `ImmichAsset`/`CachedAsset` or secrets).
- Add 1 Hz ticks, immediate events, coalescing, lifecycle/screen-off pause, and weather fetching for
  plugins that declare `weather`.
- Implement storage, actions with grants/rate limits, network proxy, external-link confirmation,
  blocked schemes, and logging/error reporting.
- Add load timeout, repeated-failure disable, watchdog, and hidden-on-failure behavior.

**Exit:** sandbox, network, action, storage, and failure tests pass; a slow/hung plugin cannot stall
the slideshow.

#### M4 — Plugin management UI

- Replace the placeholder Plugins screen with a list showing icon, name, version, and enabled state.
- Add ZIP install, details (icon/screenshots/permissions/inputs/compatibility), update, delete, and
  enable/disable.
- Add the per-plugin settings screen and route, rendering the manifest schema with validation.
- Keep app-owned labels localized; add the placement editor entry point (completed in M5).

**Exit:** widget tests for install/update/delete, per-plugin settings, immediate config updates, and
persistence.

#### M5 — Slideshow layer and placement editor

- Insert the plugin layer between media and controls; create/hide/dispose webviews with slideshow
  visibility and night mode.
- Implement normalized placement, logical size, z-order, default anchors, animation, and safe-area
  clamping.
- Add drag/resize directly over the slideshow edit mode and in the plugin screen, plus persisted grid
  snap/grid size.
- Verify click-through outside the box and controls above the plugin layer.

**Exit:** placement, safe-area, rotation, persistence, and frame-drop tests pass.

#### M6 — Bundled examples and compiled-overlay cutover

- Build clock, weather, metadata, calendar, playback, and image-info example ZIPs through the same
  manifest/host path; no special-case code.
- Seed on first run; start clock/weather/metadata enabled and the others disabled.
- Migrate `OverlaySettings` enabled state and weather location/unit/label into the weather plugin;
  add the marker that prevents deleted examples from being reseeded.
- Remove the compiled overlay widgets and old overlay toggles after migration tests pass.

**Exit:** fresh install and upgrade tests pass; examples behave exactly like third-party plugins;
deleting one is permanent; no compiled overlay remains.

#### M7 — Hardening and documentation

- Add unit/widget/integration/security/performance/migration tests, including ZIP abuse, sandbox,
  cross-plugin storage, network, links, actions, placement, and failure injection.
- Verify 1 Hz updates with video and several plugins; measure frame drops and leaks.
- Write the plugin author guide/API reference and update plugin, security, and architecture docs.

**Exit:** all Phase 4 acceptance criteria pass on Windows and modern Android; Linux is recorded as
verified or explicitly blocked; CI green.

### Critical path

```
M0 ──► M2 ──► M3 ──► M5 ──► M6 ──► M7
        ▲        ▲
M1 ─────┘        │
        M4 ──────┘
```

M1 can start while M0 runs. M4 can overlap M3 once the manifest/store is stable.

## Tasks

1. Resolve the Phase 0 overlay gate before production host work: patch CEF/OSR transparency or adopt
   an alternative, validate a Chromium 100+ Android WebView, and record evidence. Confirm the
   trade-off that below-baseline Android runs without overlays because all overlays become plugins.
2. Implement manifest models/schema and ZIP validation, including icon, screenshots, declared inputs,
   and settings.
3. Implement plugin store, registry, config, storage, lifecycle, and the compiled-overlay migration.
4. Build install/details/update/uninstall UI plus the plugin list and per-plugin settings screen.
5. Implement loopback server and host page.
6. Implement CEF and Android WebView adapters with transparency.
7. Implement sandbox/CSP/request interception and bridge protocol.
8. Implement state snapshot/coalescing/visibility lifecycle, filtered by declared inputs.
9. Implement placement/movement, slideshow edit mode, drag/resize, grid snap/grid size, and
   safe-area clamping.
10. Implement links/actions/permissions/rate limits.
11. Implement network proxy and storage APIs.
12. Implement failure isolation/baselines.
13. Build bundled example plugins, seeded through the normal install path, including
    clock/weather/metadata enabled by default.
14. Add unit/integration/security/performance/migration tests.
15. Add app lifecycle pause for background/screen-off; fetch weather for plugins that declare it;
    decide whether to populate PLG-22 tags during sync or amend the requirement.
16. Update docs and plugin author guide.

Milestone map: 1 → M0; 2–3 → M1; 5–6 → M2; 7–8, 10–12, 15 → M3; 4 → M4; 9 → M5; 13 → M6;
14, 16 → M7.

## Deliverables

- End-to-end plugin install/manage/render flow with per-plugin settings screens.
- Sandboxed interactive plugin host on desktop and Android.
- Plugin API v1 and bundled example plugins, including clock/weather/metadata.
- Drag/resize/grid placement editor.
- Security/performance/migration test evidence.
- Updated plugin/security docs.

## Acceptance criteria

- [ ] Phase 0 transparency/WebView gates are resolved and recorded on Windows, Linux, and a
      Chromium 100+ Android WebView; the no-overlay degradation below baseline is confirmed.
- [ ] A valid ZIP installs with identity, icon, description, screenshots, permissions, and requested
      inputs shown.
- [ ] Invalid/incompatible/duplicate plugins are rejected with readable errors.
- [ ] Enable/disable/update/uninstall behave correctly; resources and storage are released.
- [ ] Each installed plugin has a dedicated settings screen reachable from the plugin list.
- [ ] Clock, weather, and metadata migrate from compiled overlays to bundled example plugins; enabled state
      and weather settings are preserved.
- [ ] Plugin overlays are transparent, interactive, movable/resizable, and below app controls.
- [ ] Drag, resize, grid snap, and grid size persist and stay inside safe areas.
- [ ] Clicks outside the plugin box pass through.
- [ ] External links open in the browser after confirmation; navigation/popups are blocked.
- [ ] Plugins cannot access host storage/cookies/credentials or other plugins.
- [ ] Direct network is blocked; granted network goes through the host proxy.
- [ ] Plugin state updates at 1 Hz and on required events without dropping slideshow frames.
- [ ] A throwing/hanging plugin does not block the slideshow or controls.
- [ ] Android WebView baseline/degradation is implemented and tested.
- [ ] Bundled example plugins work; clock/weather/metadata start enabled and others disabled, and
      every example can be disabled or deleted like any third-party plugin.
- [ ] No compiled-in clock/weather/metadata overlay remains.
- [ ] CI green; docs updated.

## Risks

| Risk | Mitigation |
|---|---|
| CEF transparency is not exposed by `webview_cef` 0.6.2 | Do not start host work until a CEF/OSR transparency patch or alternative is proven; pin CEF; integration tests |
| Android reference WebView is below baseline and rendered blank | Validate on Chromium 100+ hardware/emulator; below baseline the slideshow runs without overlays |
| No app lifecycle pause | Add a `WidgetsBindingObserver` and Android screen-off signal before enabling ticks |
| Weather/tags snapshot gaps | Fetch weather for plugins that declare it; use weather plugin settings; populate tags during sync or amend PLG-22 |
| Built-in overlay migration loses or duplicates config | One-time migration from `OverlaySettings`; remove the old controls after migration; test fresh install and upgrade |
| Drag/resize/grid editor breaks safe-area or click-through | Clamp on every edit; persist normalized coordinates; test rotation and small viewports |
| Dart plugin request weakens sandbox | Keep sandboxed HTML/CSS/JS; do not execute runtime-installed native/Dart code |
| Linux OSR performance | Per-plugin small webviews; low FPS; plugin count cap |
| Plugin hangs/crashes | Per-instance isolation, timeout, watchdog, disable threshold |
| Sandbox escape | Iframe sandbox + CSP + request interception + host-only bridge |
| Plugin API churn | Version v1, compatibility checks, bundled examples updated |
| ZIP abuse | Validation/limits/fuzz tests |
| WebView diversity | Baseline check; feature detection; degradation |

## Delivery log

| Date | Result | Notes |
|---|---|---|
| 2026-11-01 | Plan revised | Audited the current app: no plugin code/host/webview deps; compiled overlays and a placeholder Plugins settings screen exist; settings/DB are schema v3 with no plugin state; no lifecycle observer; weather is tied to the compiled overlay; tags are always empty. Recorded the Phase 0 transparency/WebView gate as the entry blocker. |
| 2026-11-01 | Plugin decisions applied | All overlays become bundled example plugins (clock/weather/metadata enabled by default, migrated from `OverlaySettings`, removable like any plugin). Added per-plugin settings screens, manifest icon/inputs, plugin ZIP contents, drag/resize with grid snap, and the below-baseline no-overlay trade-off. Kept sandboxed HTML/CSS/JS. |
| 2026-11-01 | Implementation plan added | Split Phase 4 into M0–M7: overlay gate, package/persistence, host transport, bridge/capabilities, management UI, slideshow/placement, bundled examples/cutover, and hardening/docs. Added sequencing rules, file layout, milestone exits, and a critical path. |
| 2026-11-01 | M0 Windows gate passed | Vendored `webview_cef` and patched `browser_settings.background_color`; the GPU shared-texture path failed Flutter external-texture creation, so the software pixel-buffer path is used. `tool/cef_probe` verified transparency, 1 Hz JS clock, JS button/text input, Flutter overlap tap, and outside click-through. Evidence: `tool/cef_probe/evidence/m0-windows.png`. |
| 2026-11-01 | Android gate blocked | Android WebView 156 is available, but MIUI rejects `adb install` with `INSTALL_FAILED_USER_RESTRICTED`; enabling unverified apps requires a 24-hour security delay. Probe APK: `tool/android_probe/build/app/outputs/flutter-apk/app-debug.apk`. |
| 2026-11-01 | M1 complete | Manifest/settings/input/placement models, ZIP validation, DB v4 plugin tables, settings v4 plugin section, plugin store/registry/config/storage, and seeder are implemented. `flutter analyze` clean; `flutter test` 326 passed, 2 native skips. |
| 2026-11-01 | M2 host/adapters built | Loopback host server and sandbox host page with token/path/CSP/traversal tests; production `PluginWebView` with Android `webview_flutter` and desktop `webview_cef`. `flutter analyze` clean, host tests pass, Windows debug build and Android debug APK build pass. Android runtime validation remains blocked. |
| 2026-11-01 | M3 snapshot/bridge policies | Added input-filtered, redacted snapshot builder and API v1 bridge validation, outbound envelopes, action allowlist/rate limiter, link policy, and network proxy policy. Full suite 349 passed, 2 native skips; `flutter analyze` clean. Session/JS wiring and 1 Hz delivery remain. |
| 2026-11-01 | M3 session/bridge complete | Host page/SDK, `PhotoFrameHost` channel, and `PluginSession` now handle state/config/storage/actions/links/network, 1 Hz ticks, visibility/app pause, rate limits, and failure isolation. |
| 2026-11-01 | M4 plugin management UI | Plugins list, path-based ZIP install/update, enable/disable/delete, details, screenshots, schema-rendered per-plugin settings, and shell counts are implemented. File-picker dependency intentionally avoided; Android uses a path field for now. |
| 2026-11-01 | M5 slideshow layer | Plugin boxes render between media and overlays/controls; placement anchors/clamping, night visibility, 1 Hz state, edit-mode drag/resize, grid snap, click-through, and the Android controls-open fallback are implemented. Full suite 371 passed, 2 native skips; `flutter analyze` clean. |
| 2026-11-01 | M6 bundled examples and cutover | Added six bundled example ZIPs and asset seeding through the normal install path; clock/weather/metadata default enabled, others disabled. Added one-time OverlaySettings migration, deleted examples stay deleted, weather plugin config drives weather fetch, and compiled overlay widgets/toggles were removed. Migration and example validation tests added. |
| 2026-11-01 | M7 hardening/docs/runtime | Added plugin author guide and updated plugin/platform/security docs. Full suite 374 passed, 2 native skips; analyze clean; Windows debug and Android debug APK builds pass. Android production app shows real clock/metadata plugin overlays over media with 1 Hz state. Android probe verified transparency, input, text/IME, click-through, controls above, and 1 Hz updates; Windows CEF probe verified the same. The 72-hour video/frame-drop soak remains a Phase 6 gate. |
