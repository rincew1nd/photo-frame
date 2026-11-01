#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKIP_BUILD=0

if [[ "${1:-}" == "--skip-build" ]]; then
    SKIP_BUILD=1
fi

SRC="$ROOT/build/windows/x64/runner/Release"
OUT_NAME="photo-frame-windows-x64"
OUT="$ROOT/dist/$OUT_NAME"
ARCHIVE_NAME="$OUT_NAME.zip"
ARCHIVE="$ROOT/dist/$ARCHIVE_NAME"

if [[ "$SKIP_BUILD" -eq 0 ]]; then
    (cd "$ROOT" && flutter build windows --release --no-pub)
fi

if [[ ! -d "$SRC" ]]; then
    echo "Release directory not found: $SRC" >&2
    exit 1
fi

rm -rf "$OUT"
mkdir -p "$OUT" "$ROOT/dist"
cp -a "$SRC/." "$OUT/"

rm -f "$ARCHIVE"
# ponytail: powershell.exe is always present on Windows; avoids needing zip/7z.
(cd "$ROOT/dist" && powershell.exe -NoProfile -NonInteractive -Command \
    "Compress-Archive -Path '$OUT_NAME' -DestinationPath '$ARCHIVE_NAME' -Force")

echo "$ARCHIVE"
