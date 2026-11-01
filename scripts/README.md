# Packaging releases

The packaging scripts build a release artifact and stage it under `dist/`.
Run them from the repository root with Bash. On Windows use Git Bash
(`C:\Program Files\Git\bin\bash.exe`), not WSL. Each script accepts a flag to
skip the Flutter build and package an existing build instead.

## Windows x64

```bash
bash scripts/package-windows.sh
bash scripts/package-windows.sh --skip-build
```

The build runs `flutter build windows --release --no-pub` from the repo root,
copies `build/windows/x64/runner/Release` to
`dist/photo-frame-windows-x64`, and writes
`dist/photo-frame-windows-x64.zip`. The ZIP path is printed.

## Linux x64

```bash
bash scripts/package-linux.sh
bash scripts/package-linux.sh --skip-build
```

The build runs `flutter build linux --release --no-pub` from the repo root,
copies `build/linux/x64/release/bundle` to `dist/photo-frame-linux-x64`, and
writes `dist/photo-frame-linux-x64.tar.gz`. The archive path is printed.

## Android

```bash
bash scripts/package-android.sh
bash scripts/package-android.sh --skip-build
```

The build runs `flutter build apk --release --split-per-abi --no-pub` from the
repo root, copies the split `*-release.apk` files from
`build/app/outputs/flutter-apk` to `dist/photo-frame-android`, and writes
`sha256sums.txt` next to them. The output directory is printed.

Android release signing and GitHub publishing are not handled by these scripts.

# Native still codec scripts

These scripts fetch and build the native decoders used for HEIC, AVIF, and RAW
stills. They are build helpers only; the Flutter app does not run them.

## Windows x64

`fetch-stills-deps.ps1` builds libheif 1.19.7, libde265 1.0.15, dav1d 1.5.0,
and LibRaw 0.21.3 from pinned upstream sources. It requires Windows PowerShell
5.1 (not PowerShell 7) and needs an **x64 Native Tools Command Prompt for VS 2022** (or
a VS 2022 Developer PowerShell) with:

- Visual Studio 2022 C++ desktop tools (`cl.exe`)
- CMake and Ninja
- Meson (dav1d is Meson-only)
- NASM (dav1d assembly)

Run it from the repository root:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/fetch-stills-deps.ps1
```

Each component is skipped when its DLL and import library already exist. Delete
the relevant `third_party/stills/src`, `third_party/stills/build`, or
`third_party/stills/win-x64` subdirectory to force a rebuild.

Linux builds use the same components with CMake, Ninja, and Meson from the
distribution; Android builds additionally require the Android NDK. Both stage
output in the same `third_party/stills/` tree.

## Output layout

```text
third_party/stills/
  win-x64/bin/       dav1d.dll, libde265.dll, heif.dll, raw.dll
  win-x64/lib/       import libraries (dav1d.lib, libde265.lib, heif.lib, raw.lib)
  win-x64/include/   dav1d/, libde265/, libheif/, libraw/
  src/               cloned upstream sources
  build/             CMake/Meson build trees and install staging
```

`third_party/stills/` is gitignored. CI caches this directory keyed on the fetch
scripts (see `.github/workflows/ci.yml`).

## Fallback

Without the built libraries the app falls back to Immich preview images for HEIC,
AVIF, and RAW stills.

## Upstream build notes

- **dav1d** has no CMake build; it is built with Meson and Ninja, which require
  NASM for assembly.
- **LibRaw** has no `CMakeLists.txt` in its main repository. The script uses the
  separately maintained `LibRaw/LibRaw-cmake` wrapper at a pinned commit,
  pointed at the LibRaw 0.21.3 source tree with `-DLIBRAW_PATH=...`.
