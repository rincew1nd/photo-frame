# Third-party sources

## Submodules

These packages are pinned git submodules:

| Path | Upstream | Why |
|---|---|---|
| `third_party/webview_cef` | [hlwhl/webview_cef](https://github.com/hlwhl/webview_cef) 0.6.2 | Transparent plugin overlays on Windows |
| `third_party/flutter_secure_storage_windows` | [flutter_secure_storage_windows](https://pub.dev/packages/flutter_secure_storage_windows) | Windows credential storage without ATL |

Both are selected through `dependency_overrides` in `pubspec.yaml`. Clone with
submodules:

```bash
git clone --recurse-submodules <repository-url>
# or, in an existing clone:
git submodule update --init --recursive
```

The `webview_cef` fork contains the transparency, software pixel-buffer,
subprocess, input, and IME fixes that Photo Frame needs. The secure-storage
fork uses the package's Dart FFI Windows implementation and Windows Credential
Manager instead of the ATL-native plugin.

## Native still decoders

`third_party/stills/` is generated build output for HEIC, AVIF, and RAW
decoding. It is not committed. Build it with `scripts/fetch-stills-deps.ps1`
(Windows), `scripts/fetch-stills-deps.sh` (Linux), or
`scripts/build-libheif-android.sh` (Android). CI caches the directory.
