#!/usr/bin/env bash
# Smoke-tests the .dmg packing half of package_macos.sh with a stand-in .app
# (no flutter build). Exit 0 when a readable UDZO image and .sha256 appear.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

app="$work/StandIn.app"
mkdir -p "$app/Contents"
printf '%s\n' 'CFBundleName = StandIn;' >"$app/Contents/Info.plist"

out="$work/dist"
SKIP_FLUTTER_BUILD=1 APP_BUNDLE="$app" "$root/tool/package_macos.sh" "$out"

dmg="$(find "$out" -maxdepth 1 -name 'EngineStudio-*.dmg' | head -n1)"
[ -n "$dmg" ] && [ -f "$dmg" ] || { echo "No EngineStudio-*.dmg under $out" >&2; exit 1; }
[ -f "$dmg.sha256" ] || { echo "Missing $dmg.sha256" >&2; exit 1; }
# UDZO is zlib-compressed; reject empty / clearly broken outputs.
size="$(wc -c <"$dmg" | tr -d ' ')"
[ "$size" -gt 1000 ] || { echo "dmg too small ($size bytes)" >&2; exit 1; }
echo "verify_dmg_pack: ok ($dmg, $size bytes)"
