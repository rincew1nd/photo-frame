#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKIP_BUILD=0

if [[ "${1:-}" == "--skip-build" ]]; then
    SKIP_BUILD=1
fi

APK_DIR="$ROOT/build/app/outputs/flutter-apk"
OUT="$ROOT/dist/photo-frame-android"

if [[ "$SKIP_BUILD" -eq 0 ]]; then
    (cd "$ROOT" && flutter build apk --release --split-per-abi --no-pub)
fi

shopt -s nullglob
apks=("$APK_DIR"/*-release.apk)
shopt -u nullglob

if [[ "${#apks[@]}" -eq 0 ]]; then
    echo "No release APKs found in $APK_DIR" >&2
    exit 1
fi

rm -rf "$OUT"
mkdir -p "$OUT" "$ROOT/dist"
for apk in "${apks[@]}"; do
    cp "$apk" "$OUT/"
done

(cd "$OUT" && sha256sum ./*-release.apk > sha256sums.txt)

echo "$OUT"
