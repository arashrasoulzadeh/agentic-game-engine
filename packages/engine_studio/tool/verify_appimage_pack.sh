#!/usr/bin/env bash
# Smoke-tests the AppDir packing half of package_linux.sh with a stand-in
# AppDir (no flutter build). Exit 0 when a readable .AppDir.tar.gz and
# .sha256 appear.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

appdir="$work/EngineStudio.AppDir"
mkdir -p "$appdir/usr/bin"
printf '%s\n' '#!/bin/sh' 'echo stand-in' >"$appdir/usr/bin/engine_studio"
chmod +x "$appdir/usr/bin/engine_studio"
printf '%s\n' '#!/bin/sh' 'exec "$PWD/usr/bin/engine_studio" "$@"' >"$appdir/AppRun"
chmod +x "$appdir/AppRun"
printf '%s\n' '[Desktop Entry]' 'Name=Engine Studio' 'Exec=engine_studio' 'Type=Application' \
  >"$appdir/engine-studio.desktop"

out="$work/dist"
SKIP_FLUTTER_BUILD=1 APP_DIR="$appdir" "$root/tool/package_linux.sh" "$out"

archive="$(find "$out" -maxdepth 1 -name 'EngineStudio-*.AppDir.tar.gz' | head -n1)"
[ -n "$archive" ] && [ -f "$archive" ] || { echo "No EngineStudio-*.AppDir.tar.gz under $out" >&2; exit 1; }
[ -f "$archive.sha256" ] || { echo "Missing $archive.sha256" >&2; exit 1; }
size="$(wc -c <"$archive" | tr -d ' ')"
[ "$size" -gt 100 ] || { echo "archive too small ($size bytes)" >&2; exit 1; }
echo "verify_appimage_pack: ok ($archive, $size bytes)"
