# Implementation Plans

Status: Draft v0.1
Last updated: 2026-10-31
Technical documentation: [`../Docs/README.md`](../Docs/README.md)
Product requirements: [`../REQUIREMENTS.md`](../REQUIREMENTS.md)

Implementation is split into phases. Each phase has a goal, explicit scope, deliverables, exit
criteria, and risks. A phase is not complete until its exit criteria are met on Windows, Linux x64,
and Android as applicable.

## Phase overview

| Phase | Name | Goal | Gate |
|---|---|---|---|
| 0 | [Technical spike](phase-0-spike.md) | Prove the risky parts before production code | Go/no-go on media, CEF transparency/input, Android z-order, decoders |
| 1 | [Foundation](phase-1-foundation.md) | App scaffold, Immich connection/auth, settings, storage, CI | Connect and persist a working session |
| 2 | [Photos and cache](phase-2-photos-cache.md) | Photo slideshow, cache/offline, filters, profiles, settings UI | Play cached photos offline with filters/profiles |
| 3 | [Media](phase-3-media.md) | Video, audio, Live Photos, HEIC/AVIF, DNG/ProRAW, tone-mapping | Original media plays with correct controls/audio |
| 4 | [Plugins](phase-4-plugins.md) | ZIP install, sandbox, host bridge, placement, actions, bundled example plugins | Interactive sandboxed plugin above video |
| 5 | [Platform integration](phase-5-platform.md) | Boot/launcher, kiosk, sleep, biometrics, updates, diagnostics | Unattended frame behaviour on all targets |
| 6 | [Hardening and release](phase-6-hardening-release.md) | Soak, security, performance, docs, signed release | Release checklist complete |

## Sequencing

```
Phase 0 -> Phase 1 -> Phase 2 -> Phase 3 -> Phase 4 -> Phase 5 -> Phase 6
                \-> platform channels skeleton can start in Phase 1
                         \-> packaging/CI evolves continuously
```

- Phase 0 must pass before production investment in the plugin host and media pipeline.
- Phase 1 can begin the scaffold while Phase 0 results are being written, but the main stack
  decision is not reopened unless Phase 0 fails.
- Phases 2 and 3 can overlap partially (image pipeline and cache).
- Phase 4 depends on Phase 3 for video/photo layering and on Phase 1 for settings/storage.
- Phase 5 depends on a working slideshow and plugin host.
- Phase 6 is a release gate, not a place to hide unfinished work.

## Status tracking

Each phase file starts with a status line:

- `Not started`
- `In progress`
- `Blocked`
- `Done`

Update the phase file when work starts and when exit criteria are met. Keep a short delivery log at
the bottom of each file.

## Phase rules

- Scope is explicit. Items in “Out of scope” do not creep in without updating the plan.
- Each phase adds tests and documentation in the same change.
- No phase may regress earlier acceptance criteria.
- Performance/security budgets are verified, not assumed.
- Architecture deviations require an ADR update or a new ADR.
- Requirements-affecting decisions are reflected in
  [`../Docs/requirements-alignment.md`](../Docs/requirements-alignment.md).
- Release artifacts are not produced from a phase with open blockers.

## Definition of done

A phase is done when:

- its acceptance criteria pass;
- tests are added and green;
- docs are updated;
- earlier phases still pass;
- known risks are recorded;
- the demo/verification evidence is linked or described.

## Current status

Phase 0 is `Done (conditional go)`; see `Docs/spike-0-results.md`. Phases 1–2 are `Done
(automated/API verification; platform-runtime verification partial)`; see
[`../Docs/phase-1-2-verification.md`](../Docs/phase-1-2-verification.md). Phase 3 is implemented with
verification gaps: HDR tuning, Linux/Android native library builds, and broader runtime testing.
Phase 4 is in progress: the Windows overlay gate passed, M1 package/persistence is complete, and M2's loopback host plus webview adapters are built; Android runtime validation is blocked by a MIUI USB-install restriction. Phase 5 is in progress: Android boot/HOME/security plumbing, night
brightness, diagnostics, desktop automation, single-instance focus, and packaging scripts are
implemented.
Updates, full kiosk lockdown, Linux runtime validation, localization, and audio focus remain. There
is no Linux host or release channel/keystore.
