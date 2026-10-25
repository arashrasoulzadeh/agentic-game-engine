#!/usr/bin/env bash
# Smoke-tests the Windows packing half of package_windows.sh with a
# stand-in Release folder (no flutter build). Exit 0 when a readable
# archive and .sha256 appear.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

appdir="$work/Release"
mkdir -p "$appdir/data/flutter_assets"
printf '%s\n' 'stand-in' >"$appdir/engine_studio.exe"
printf '%s\n' 'data' >"$appdir/data/flutter_assets/.keep"

out="$work/dist"
SKIP_FLUTTER_BUILD=1 APP_DIR="$appdir" "$root/tool/package_windows.sh" "$out"

archive="$(find "$out" -maxdepth 1 \( -name 'EngineStudio-*-windows.zip' -o -name 'EngineStudio-*-windows.tar.gz' \) | head -n1)"
[ -n "$archive" ] && [ -f "$archive" ] || { echo "No EngineStudio-*-windows archive under $out" >&2; exit 1; }
[ -f "$archive.sha256" ] || { echo "Missing $archive.sha256" >&2; exit 1; }
size="$(wc -c <"$archive" | tr -d ' ')"
[ "$size" -gt 20 ] || { echo "archive too small ($size bytes)" >&2; exit 1; }
echo "verify_windows_pack: ok ($archive, $size bytes)"
