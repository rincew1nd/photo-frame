# Phase 1 — Foundation

Status: Done (automated/API verification; Android launch and CI run pending)
Depends on: Phase 0 go
Unblocks: Phase 2, Phase 3, Phase 4

## Goal

Create the production Flutter application skeleton and prove the complete connection path: a user
can configure an Immich server, authenticate, verify permissions, select albums, and restart the
app with the session and settings intact.

## Scope

### Application shell

- Flutter project with application ID/namespace `com.rincew1nd.photoframe`.
- Version `1.0.0+1`; new Android signing configuration.
- Material 3 theme, go_router, Riverpod, feature-first folder structure.
- Logging with rotation and secret redaction; global crash handler.
- Localization infrastructure (ARB, English fallback).
- Single-instance skeleton on desktop.
- CI skeleton for analyze/test/build on Windows, Linux, Android.

### Immich connection

- Server URL validation.
- API key entry and secure storage.
- OAuth PKCE plumbing (Android custom scheme; desktop loopback).
- API key generation after login where supported.
- Five-permission verification and degradation.
- Immich API client with typed DTOs, paging, error mapping, and `x-api-key` interceptor.
- Album list and multi-selection; persistence.
- Connection & Security settings screen.

### Persistence

- Drift database initialization and migration harness.
- Typed settings repository with defaults and migrations.
- Secure storage abstraction.
- Minimal cache directories/path provider setup.
- No media download yet.

### Settings shell

- Grouped settings scaffold with expand/collapse and summaries.
- First group expanded; persistence of expansion state.
- Placeholder groups for later phases.
- Onboarding tour target registry (structure only).

### Platform skeleton

- Platform service interfaces: secure storage, paths, keep-awake, autostart, brightness,
  biometrics, updates.
- Platform implementation stubs for Android, Windows, and Linux (no iOS).
- Android Kotlin plugin scaffold for future boot/brightness/installer work.
- No start-on-boot/launcher implementation yet.

## Out of scope

- Slideshow and media playback.
- Cache download/offline.
- Plugin system.
- Night mode, biometric gating UI, start-on-boot, updates.
- Production packaging/signing beyond a debug build.

## Tasks

1. Scaffold the Flutter project and app identity.
2. Add lint/format/analyze configuration and CI.
3. Implement logging, crash handling, error types, and redaction tests.
4. Implement Drift + settings repository + secure storage.
5. Implement the Immich DTOs and API client.
6. Implement auth and permission checks; add a mock Immich server for tests.
7. Implement album listing/selection and persistence.
8. Build the setup and connection/security screens.
9. Build the settings shell, groups, and tour target registry.
10. Add platform service interfaces and stubs.
11. Add unit/widget tests and a smoke integration test.
12. Update docs for any deviations found during implementation.

## Deliverables

- Buildable Windows, Linux, and Android app.
- Working Immich setup/login/permission/album flow.
- Persisted settings and secure credentials.
- CI pipeline with green analyze/test/build.
- Tests for auth, permissions, settings, and DTO parsing.
- Updated documentation for any deviations.

## Acceptance criteria

- [ ] App launches on Windows, Linux x64, and Android 8+. (Windows launch verified; Android APK builds; Linux/Android runtime pending.)
- [x] API-key setup verified against a mock server and the real Immich 3.3.5 API; full manual UI flow pending.
- [x] OAuth PKCE flow is implemented for Android and desktop (API-key entry remains available as a
      fallback).
- [x] The five permissions are verified; `asset.download` degradation is represented.
- [x] Albums list and multi-selection persist across restart.
- [x] Settings persist across restart and process death.
- [x] API key/tokens never appear in logs or settings files.
- [x] Settings groups render and persist expansion state.
- [ ] CI is green on all three targets. (Not run; workflows configured.)
- [x] No debug-only hacks remain in the connection path.

## Risks

| Risk | Mitigation |
|---|---|
| Immich OAuth redirect restrictions | Validate against a real server early; fall back to API key entry |
| Desktop secure storage backend differences | Abstract and verify Windows/Linux; fail closed for secrets |
| Settings schema churn | Versioned repository with migrations from day one |
| CI build time (Flutter + native deps) | Add native deps later; cache Flutter SDK/packages |

## Out of scope for exit

The phase does not need slideshow, media, plugins, kiosk, boot, or release packaging.

## Delivery log

| Date | Result | Notes |
|---|---|---|
| - | - | - |
| 2026-10-27 | Done (verification partial) | Flutter app scaffolded with identity `com.rincew1nd.photoframe`, API 26, CI config, settings/secure storage/paths/logging/redaction, platform service stubs, Immich v3 client and mock server, API-key and OAuth PKCE flows, five-permission report, album selection, setup/albums/settings/connection screens. 167 tests green at the end of Phase 2; Windows debug build succeeds; Android debug APK builds. Real Immich 3.3.5 read-only check: user, 23 albums, 8-asset album, all five permissions granted. Android runtime launch and Linux/CI execution were not completed after the device disconnected; see `Docs/phase-1-2-verification.md`. |
