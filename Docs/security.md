# Security and Privacy

## 1. Assets to protect

- Immich API key and OAuth tokens.
- Immich server URL and credentials.
- User photos, videos, metadata, and cached originals.
- Plugin configuration and storage.
- App integrity and update channel.

The app is a local photo frame. The main attack surfaces are the network (Immich/GitHub/weather),
installed plugin bundles, the local plugin server, the webview/CEF engine, and the update path.

## 2. Secrets

- API key/OAuth tokens are stored in platform secure storage.
- Secrets are never written to logs, crash reports, settings files, cache metadata, plugin
  snapshots, or URLs.
- Media requests use `x-api-key` headers, not query parameters.
- Log redaction covers `x-api-key`, `Authorization`, cookies, and token-like values.
- The API-key reveal/copy action is protected by biometric/device credential where a screen lock
  exists.
- Logout clears tokens and credentials; cached media remains until the user clears it.

## 3. Authentication and permissions

- API key validation and the five permission checks occur after connection.
- OAuth uses PKCE; no client secret is embedded.
- Desktop OAuth uses a loopback redirect; Android uses the app’s custom scheme.
- Blocking permissions prevent setup; optional permission (`asset.download`) degrades features.
- Android declares `RECEIVE_BOOT_COMPLETED`, `WAKE_LOCK`, `USE_BIOMETRIC`, `USE_FINGERPRINT`, and
  `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`; all are granted at install and no runtime permissions are
  requested. Battery-optimization exemption is a user-granted special access for start-on-boot; the
  app does not bypass it.
- The app never sends credentials to plugins or third-party services.
- Immich connection may be HTTP on a LAN; the UI should warn when the URL is not HTTPS. TLS
  certificate validation is not disabled.

## 4. Plugin sandbox

### Isolation

- Each plugin runs in a sandboxed iframe inside a transparent webview.
- Opaque origin: no host cookies, localStorage, IndexedDB, or same-origin access.
- No native APIs, filesystem, shell, registry, or app database access.
- No direct access to other plugins or their storage.
- Plugin code cannot inject code into the host.

### Host bridge

- JSON messages only; schema and size validated.
- Origin/frame checks on the host page.
- Unknown messages/actions are ignored.
- Actions are permission-gated, declared in the manifest, user-granted, and rate-limited.
- Plugins cannot change permissions, credentials, server settings, or other plugin configuration.

### Content

- Plugin ZIPs are validated for traversal, bombs, file count/size, manifest schema, entry presence,
  icon/screenshot/asset types, and declared snapshot inputs.
- No native binaries, executables, or remote code includes.
- Icons and screenshots are displayed as images, not executed.
- Plugins may contain external links; they open in the system browser after confirmation, not
  inside the plugin.
- Navigation to `file:`, `javascript:`, `intent:`, `data:` and popups is blocked.

### Network

- Denied by default; explicit user consent.
- Direct requests are blocked by CSP and native request interception.
- Granted requests go through a host proxy with timeouts, size limits, rate limits, and no
  credentials.
- Plugins cannot reach Immich, secure storage, or app-local endpoints.
- Domain allowlists are not implemented in v1; document the residual risk.
- Remote images/fonts are not automatically allowed; plugins should bundle assets. They must fail
  gracefully.

### Storage

- Host-managed, namespaced, size-limited, and removed on uninstall.
- Values are validated/serialized; no executable content.

### Failure isolation

- Per-instance webview and watchdog.
- Repeated failures disable the plugin and log the reason.
- A hung plugin cannot block the slideshow or app controls.
- Plugin webviews are hidden/paused when the slideshow is hidden or the screen is off.

## 5. Local loopback server

- Binds to `127.0.0.1`; ephemeral port.
- Random per-session token in the URL; per-plugin paths.
- Serves only the host page and the current plugin’s assets.
- Rejects traversal, symlinks, directory listing, and unknown paths.
- CORS limited to the host/plugin origins.
- No API key, no Immich proxy, no app database.
- Lifetime tied to the app; stop/teardown on exit.
- Rate/size limits and request logging without secrets.

Residual risks: other local processes can connect to loopback. The token and path restrictions
reduce exposure; do not expose the server on non-loopback interfaces.

## 6. Plugin supply chain

- V1 installs local ZIPs only; no marketplace or remote URL install.
- Bundled example plugins are seeded from app assets at first run; they are first-party examples and
  can be disabled or uninstalled like any plugin.
- No signatures in v1. The user sees identity, author, version, description, icon, screenshots,
  permissions, requested inputs, and license before activation of a third-party ZIP.
- SHA-256 is recorded for integrity/update comparison, not as a trust signature.
- Updates require explicit confirmation when permissions or settings compatibility change.
- A future version may add signatures and a curated catalog.

## 7. Updates

- In-app update checks, APK download/install, and desktop update flows are not implemented. No update
  path currently exists.
- Android APK updates, when added, must be signed; the system installer verifies signature and
  package identity.
- Desktop artifacts are published with checksums.
- In-app update checks must not execute arbitrary remote code.
- Plugin updates are local ZIP imports, not remote code fetch.
- Release notes document permission or security changes.

## 8. Data at rest

- The cache contains user media and is app-private.
- The cache is not separately encrypted; OS disk encryption is the boundary.
- API key/OAuth tokens are encrypted via platform secure storage.
- Plugin storage is app-private and removed on uninstall.
- Logs are local, rotated, and redacted; sharing logs is an explicit user action.

## 9. Biometrics

- Android: biometric/device credential gate for media selection and API-key reveal/copy when a lock
  exists; fails open without a lock (BR-07).
- Windows: Windows Hello if available; fails open otherwise.
- Linux: no standard equivalent; fails open.
- Biometric prompts do not expose secrets; failure returns to the app without revealing data.

## 10. DoS and resource limits

- Plugin ZIP/file/size limits.
- Webview load timeouts and failure thresholds.
- Network proxy timeouts, response-size limits, and rate limits.
- Action rate limits.
- Bounded image cache and cache quota.
- One active player; disposed players on slide change.
- Watchdog for media/plugin hosts.
- Disk-full and network-down handling without data loss.

## 11. Logging and diagnostics

- File logs rotate; no secrets.
- Crash reports are local; no automatic upload.
- About & diagnostics shows app version/build, plugin API v1, platform/OS version, cache statistics,
  recent redacted logs, error count with copy, and opens the Flutter license page.
- WebView/CEF versions are not shown in diagnostics.
- Plugin errors are attributed by plugin ID/instance without leaking library data.
- Log sharing is user-initiated.

## 12. Residual risks

| Risk | Status |
|---|---|
| Malicious plugin with network permission can access arbitrary HTTP(S) via proxy | Accepted for v1; user consent; future allowlist |
| Local loopback server reachable by local processes | Mitigated by loopback/token/path; not eliminated |
| No plugin signatures | Accepted for v1; explicit install/consent |
| HEVC/Dolby Vision patent licensing | Legal, not a runtime control |
| Old Android WebView | Mitigated by version check/plugin degradation |
| CEF/webview engine vulnerabilities | Keep CEF/system WebView updated; pin/bump releases |
| HTTP Immich URL on LAN | Warn; user chooses; TLS validation remains on |
| Unencrypted local media cache | OS disk encryption boundary |
| No in-app update path or update-signature verification | Accepted for v1; users install published artifacts manually |
| Plugin icons/screenshots could contain misleading content | Shown as untrusted images; user consents |

## 13. Security testing

Automated coverage includes secret redaction, settings migrations, cache, API-key reveal/copy
gating, plugin ZIP/manifest validation, bridge/session policy, and loopback-server isolation.
Update-signature testing does not apply until an update flow exists.

- Secret redaction tests.
- ZIP traversal/bomb/oversize tests.
- Sandbox: no host storage/cookies, no cross-plugin access.
- Network: direct fetch blocked; proxy permission/revocation; timeouts/limits.
- Links: external confirmation, blocked schemes/popups.
- Action/permission/rate-limit tests.
- Loopback server path/traversal/token tests.
- Soak/failure injection: hung plugin, killed webview, disk full, auth revoked.
