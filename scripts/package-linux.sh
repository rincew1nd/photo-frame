#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKIP_BUILD=0

if [[ "${1:-}" == "--skip-build" ]]; then
    SKIP_BUILD=1
fi

SRC="$ROOT/build/linux/x64/release/bundle"
OUT="$ROOT/dist/photo-frame-linux-x64"
ARCHIVE="$OUT.tar.gz"

if [[ "$SKIP_BUILD" -eq 0 ]]; then
    (cd "$ROOT" && flutter build linux --release --no-pub)
fi

if [[ ! -d "$SRC" ]]; then
    echo "Bundle directory not found: $SRC" >&2
    exit 1
fi

rm -rf "$OUT"
mkdir -p "$OUT" "$ROOT/dist"
cp -a "$SRC/." "$OUT/"

rm -f "$ARCHIVE"
tar -czf "$ARCHIVE" -C "$ROOT/dist" "photo-frame-linux-x64"

echo "$ARCHIVE"
