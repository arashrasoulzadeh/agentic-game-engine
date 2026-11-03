#!/usr/bin/env bash
# Builds the studio for Windows and packs a portable zip.
#
#   tool/package_windows.sh [output-dir]      (default: build/dist)
#
# Always writes:
#   EngineStudio-<version>-windows.zip (+ .sha256)
#
# If WiX (`candle` + `light`) is on PATH and a `.wxs` is provided via
# WIX_SOURCE, also writes EngineStudio-<version>.msi (+ .sha256). Real MSI
# authoring + signing stay release-time; this script is the packing half.
#
# Packing only (no flutter build) — used by verify_windows_pack.sh:
#   SKIP_FLUTTER_BUILD=1 APP_DIR=/path/to/Release tool/package_windows.sh /tmp/dist
set -euo pipefail

cd "$(dirname "$0")/.."
out="${1:-build/dist}"
version="$(sed -n 's/^version: *\([0-9][^+ ]*\).*/\1/p' pubspec.yaml | head -n1)"
version="${version:-0.0.0}"

if [[ "${SKIP_FLUTTER_BUILD:-}" != "1" ]]; then
  # shellcheck disable=SC2086
  flutter build windows --release ${FLUTTER_ARGS:-}
  products="build/windows/x64/runner/Release"
  [ -d "$products" ] || { echo "No Windows release under $products" >&2; exit 1; }
  appdir="$products"
else
  appdir="${APP_DIR:?APP_DIR must point at a Release folder when SKIP_FLUTTER_BUILD=1}"
  [ -d "$appdir" ] || { echo "APP_DIR is not a directory: $appdir" >&2; exit 1; }
fi

mkdir -p "$out"
zipfile="$out/EngineStudio-$version-windows.zip"
rm -f "$zipfile"
# Prefer zip; fall back to tar.gz on hosts without zip (some CI images).
if command -v zip >/dev/null 2>&1; then
  (cd "$appdir" && zip -qr "$zipfile" .)
else
  zipfile="$out/EngineStudio-$version-windows.tar.gz"
  tar -C "$appdir" -czf "$zipfile" .
fi
shasum -a 256 "$zipfile" | awk '{print $1}' >"$zipfile.sha256"
echo "Wrote $zipfile"
echo "sha256 $(cat "$zipfile.sha256")"

if [[ -n "${WIX_SOURCE:-}" ]] && command -v candle >/dev/null 2>&1 && command -v light >/dev/null 2>&1; then
  wix_out="$out/wix"
  mkdir -p "$wix_out"
  candle -o "$wix_out/" "$WIX_SOURCE"
  light -o "$out/EngineStudio-$version.msi" "$wix_out"/*.wixobj
  shasum -a 256 "$out/EngineStudio-$version.msi" | awk '{print $1}' >"$out/EngineStudio-$version.msi.sha256"
  echo "Wrote $out/EngineStudio-$version.msi"
else
  echo "WiX not configured — skipped .msi (portable zip is enough for CI)."
fi
