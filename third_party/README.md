# Third-party sources

## webview_cef

Vendored copy of `webview_cef` 0.6.2 (Apache-2.0), selected via the
`dependency_overrides` path in `pubspec.yaml`.

Local patches support transparent plugin overlays on Windows:

- transparent offscreen browser background;
- software pixel-buffer rendering when the GPU shared-texture path fails;
- CEF subprocess and message-loop hooks in `windows/runner/main.cpp`;
- input, IME, and windowless-rendering fixes.

The downloaded CEF runtime under `third/cef/` and `third/prebuilt.zip` is
ignored and fetched by CMake. Do not commit it.

Upstream: <https://github.com/hlwhl/webview_cef>. There is currently no remote
fork for these local patches, so the patched source is tracked directly here.
If a fork is published, replace this directory with a pinned submodule and keep
the patch commits in that fork.

## flutter_secure_storage_windows

Tracked local patch for the Windows secure-storage plugin, selected via
`dependency_overrides`.

## stills

Native HEIC/AVIF/RAW decoder build output. Ignored; reproduce with
`scripts/fetch-stills-deps.ps1` / `.sh` and
`scripts/build-libheif-android.sh`.
