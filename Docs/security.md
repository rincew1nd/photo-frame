# Security and Privacy

Status: Draft v0.1
Related: [`plugins.md`](plugins.md), [`data-cache.md`](data-cache.md), [`licensing.md`](licensing.md)

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
  and screenshot/asset types.
- No native binaries, executables, or remote code includes.
- Screenshots are displayed as images, not executed.
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
- No signatures in v1. The user sees identity, author, version, description, screenshots,
  permissions, and license before activation.
- SHA-256 is recorded for integrity/update comparison, not as a trust signature.
- Updates require explicit confirmation when permissions or settings compatibility change.
- A future version may add signatures and a curated catalog.

## 7. Updates

- Android APKs are signed; the system installer verifies the signature and package identity.
- Desktop artifacts are downloaded from GitHub releases; checksums should be published.
- In-app update checks do not execute arbitrary remote code.
- Plugin updates are local ZIP imports, not remote code fetch.
- Release notes document permission or security changes.

## 8. Data at rest

- The cache contains user media and is app-private.
- The cache is not separately encrypted; OS disk encryption is the boundary.
- API key/OAuth tokens are encrypted via platform secure storage.
- Plugin storage is app-private and removed on uninstall.
- Logs are local, rotated, and redacted; sharing logs is an explicit user action.

## 9. Biometrics

- Android: biometric/device credential for media/library navigation and key reveal/copy when a lock
  exists; fail-open for navigation without a lock (BR-07).
- Windows: Windows Hello if available; fail-open otherwise.
- Linux: no standard equivalent; fail-open and document.
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
- Diagnostics include app version, plugin API version, platform, WebView/CEF version, cache stats,
  and recent redacted errors.
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
| Plugin screenshots could contain misleading content | Shown as untrusted images; user consents |

## 13. Security testing

- Secret redaction tests.
- ZIP traversal/bomb/oversize tests.
- Sandbox: no host storage/cookies, no cross-plugin access.
- Network: direct fetch blocked; proxy permission/revocation; timeouts/limits.
- Links: external confirmation, blocked schemes/popups.
- Action/permission/rate-limit tests.
- Loopback server path/traversal/token tests.
- Update signature/package checks.
- Soak/failure injection: hung plugin, killed webview, disk full, auth revoked.
