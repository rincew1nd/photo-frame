# Phase 4 — Plugin System

Status: Not started
Depends on: Phase 3, Phase 1 (settings/storage)
Unblocks: Phase 5

## Goal

Deliver the complete plugin lifecycle and rendering host: local ZIP install/update, transparent
interactive overlays, sandboxing, host-mediated network/storage/actions, movable placement, and
reference plugins.

## Scope

### Bundle and manifest

- ZIP layout with `plugin.json`, entry HTML, CSS, optional JS/assets/screenshots.
- Manifest schema: id, name, version, apiVersion, minAppVersion, author, license, description,
  entry, screenshots, permissions, actions, updateTriggers, placement, settings.
- Validation: schema, traversal, bombs, limits, duplicate IDs, API compatibility, entry/screenshots.
- SHA-256 recorded.

### Lifecycle and UI

- Install from local ZIP.
- Install/details UI: identity, description, screenshots, permissions, compatibility, license.
- Enable/disable, update, uninstall, inspect.
- Update preserves compatible config; incompatible schema requires confirmation.
- Uninstall removes bundles/config/storage.
- Plugin list and settings screens.
- Placement editor and per-instance visibility/night-mode option.

### Host and rendering

- Per-instance transparent webview:
  - CEF/`webview_cef` on Windows/Linux;
  - system WebView/`webview_flutter` on Android.
- Loopback server with ephemeral port/token; host page and plugin assets.
- Sandboxed iframe; opaque origin; CSP; no host storage/cookies.
- Host-owned placement: default, plugin request, clamp to safe area, animate, persist.
- Click-through outside the plugin box.
- App controls/dialogs above; Android hide-overlay fallback if required.
- Input: buttons, links, text where supported; IME.
- External links intercepted/opened in system browser with confirmation; blocked schemes/popups.

### Bridge and API v1

- State snapshot (app/time/weather/playback/image/config/placement).
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
- Bundled, disabled by default; descriptions/screenshots; settings/time-tick/image-change demos.
- Built-in overlays remain.

## Out of scope

- Marketplace, remote install, signatures, multiple instances per plugin.
- Plugins outside the slideshow.
- Plugin access to Immich/library/credentials.
- Native code plugins/background services.
- App-provided calendar feeds.
- Remote asset allowlists (future).

## Tasks

1. Implement manifest models/schema and ZIP validation.
2. Implement plugin store, registry, config, storage, lifecycle.
3. Build install/details/update/uninstall UI with screenshots and permissions.
4. Implement loopback server and host page.
5. Implement CEF and Android WebView adapters with transparency.
6. Implement sandbox/CSP/request interception and bridge protocol.
7. Implement state snapshot/coalescing/visibility lifecycle.
8. Implement placement/movement and safe-area clamping.
9. Implement links/actions/permissions/rate limits.
10. Implement network proxy and storage APIs.
11. Implement failure isolation/baselines.
12. Build reference plugins.
13. Add unit/integration/security/performance tests.
14. Update docs and plugin author guide.

## Deliverables

- End-to-end plugin install/manage/render flow.
- Sandboxed interactive plugin host on desktop and Android.
- Plugin API v1 and reference plugins.
- Security/performance test evidence.
- Updated plugin/security docs.

## Acceptance criteria

- [ ] A valid ZIP installs with identity, description, screenshots, and permissions shown.
- [ ] Invalid/incompatible/duplicate plugins are rejected with readable errors.
- [ ] Enable/disable/update/uninstall behave correctly; resources and storage are released.
- [ ] Plugin overlays are transparent, interactive, movable, and below app controls.
- [ ] Clicks outside the plugin box pass through.
- [ ] External links open in the browser after confirmation; navigation/popups are blocked.
- [ ] Plugins cannot access host storage/cookies/credentials or other plugins.
- [ ] Direct network is blocked; granted network goes through the host proxy.
- [ ] Plugin state updates at 1 Hz and on required events without dropping slideshow frames.
- [ ] A throwing/hanging plugin does not block the slideshow or controls.
- [ ] Android WebView baseline/degradation is implemented and tested.
- [ ] Reference plugins work and are disabled by default.
- [ ] Built-in overlays remain available.
- [ ] CI green; docs updated.

## Risks

| Risk | Mitigation |
|---|---|
| CEF transparency/input regression | Phase 0 patch; pin CEF; integration tests |
| Android z-order blocks controls | Hide plugin webviews while controls/dialogs are open |
| Linux OSR performance | Per-plugin small webviews; low FPS; plugin count cap |
| Plugin hangs/crashes | Per-instance isolation, timeout, watchdog, disable threshold |
| Sandbox escape | Iframe sandbox + CSP + request interception + host-only bridge |
| Plugin API churn | Version v1, compatibility checks, reference plugins updated |
| ZIP abuse | Validation/limits/fuzz tests |
| WebView diversity | Baseline check; feature detection; degradation |

## Delivery log

| Date | Result | Notes |
|---|---|---|
| - | - | - |
