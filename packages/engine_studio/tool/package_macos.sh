#!/usr/bin/env bash
# Builds the studio for macOS and packs it into a .dmg.
#
#   tool/package_macos.sh [output-dir]      (default: build/dist)
#
# Produces <output-dir>/EngineStudio-<version>.dmg and a .sha256 next to it, the checksum the
# release manifest lists for the download. The app is NOT code-signed or notarized here: do that
# before publishing (codesign + notarytool), or Gatekeeper will refuse to open it.
set -euo pipefail

cd "$(dirname "$0")/.."
out="${1:-build/dist}"
version="$(sed -n 's/^version: *\([0-9][^+ ]*\).*/\1/p' pubspec.yaml | head -n1)"
version="${version:-0.0.0}"

# FLUTTER_ARGS passes extra flags through, e.g. FLUTTER_ARGS=--no-pub when offline.
# shellcheck disable=SC2086
flutter build macos --release ${FLUTTER_ARGS:-}

products="build/macos/Build/Products/Release"
# The product name follows the Xcode project, so take whatever .app was built.
app="$(find "$products" -maxdepth 1 -name '*.app' | head -n1)"
[ -n "$app" ] && [ -d "$app" ] || { echo "No .app found under $products" >&2; exit 1; }

mkdir -p "$out"
dmg="$out/EngineStudio-$version.dmg"
staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
cp -R "$app" "$staging/"
ln -s /Applications "$staging/Applications"   # drag-to-install target

rm -f "$dmg"
hdiutil create -volname "Engine Studio" -srcfolder "$staging" -ov -format UDZO "$dmg" >/dev/null
shasum -a 256 "$dmg" | awk '{print $1}' > "$dmg.sha256"
echo "Wrote $dmg"
echo "sha256 $(cat "$dmg.sha256")"
