# Phase 4 — Plugin System

Status: Not started (blocked on the Phase 0 transparent-overlay/WebView gate)
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
  coordinates. These fields are the migration source for the bundled plugins; they must not remain
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
  drag/resize/grid snapping, plugin storage, or reference plugins.
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
drag/resize/grid placement, and bundled reference plugins that replace the current compiled
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
- Migrate compiled clock/weather/metadata state into bundled plugins; remove the compiled overlay
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

### Reference plugins

- Clock/time, calendar/date, weather, playback status, image info.
- Bundled; clock/weather/metadata enabled by default, other reference plugins disabled.
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
13. Build bundled reference plugins, including clock/weather/metadata enabled by default.
14. Add unit/integration/security/performance/migration tests.
15. Add app lifecycle pause for background/screen-off; fetch weather for plugins that declare it;
    decide whether to populate PLG-22 tags during sync or amend the requirement.
16. Update docs and plugin author guide.

## Deliverables

- End-to-end plugin install/manage/render flow with per-plugin settings screens.
- Sandboxed interactive plugin host on desktop and Android.
- Plugin API v1 and bundled reference plugins, including clock/weather/metadata.
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
- [ ] Clock, weather, and metadata migrate from compiled overlays to bundled plugins; enabled state
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
- [ ] Reference plugins work; clock/weather/metadata are enabled by default and others are disabled.
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
| Plugin API churn | Version v1, compatibility checks, reference plugins updated |
| ZIP abuse | Validation/limits/fuzz tests |
| WebView diversity | Baseline check; feature detection; degradation |

## Delivery log

| Date | Result | Notes |
|---|---|---|
| 2026-11-01 | Plan revised | Audited the current app: no plugin code/host/webview deps; compiled overlays and a placeholder Plugins settings screen exist; settings/DB are schema v3 with no plugin state; no lifecycle observer; weather is tied to the compiled overlay; tags are always empty. Recorded the Phase 0 transparency/WebView gate as the entry blocker. |
| 2026-11-01 | Plugin decisions applied | All overlays become bundled plugins (clock/weather/metadata enabled by default, migrated from `OverlaySettings`). Added per-plugin settings screens, manifest icon/inputs, plugin ZIP contents, drag/resize with grid snap, and the below-baseline no-overlay trade-off. Kept sandboxed HTML/CSS/JS. |
