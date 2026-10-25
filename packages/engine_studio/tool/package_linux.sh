#!/usr/bin/env bash
# Builds the studio for Linux and packs a portable AppDir archive.
#
#   tool/package_linux.sh [output-dir]      (default: build/dist)
#
# Always writes:
#   EngineStudio-<version>.AppDir.tar.gz (+ .sha256)
#
# If `appimagetool` is on PATH, also writes:
#   EngineStudio-<version>.AppImage (+ .sha256)
#
# Packing only (no flutter build) — used by verify_appimage_pack.sh:
#   SKIP_FLUTTER_BUILD=1 APP_DIR=/path/to/AppDir tool/package_linux.sh /tmp/dist
set -euo pipefail

cd "$(dirname "$0")/.."
out="${1:-build/dist}"
version="$(sed -n 's/^version: *\([0-9][^+ ]*\).*/\1/p' pubspec.yaml | head -n1)"
version="${version:-0.0.0}"

if [[ "${SKIP_FLUTTER_BUILD:-}" != "1" ]]; then
  # shellcheck disable=SC2086
  flutter build linux --release ${FLUTTER_ARGS:-}

  products="build/linux/x64/release/bundle"
  [ -d "$products" ] || { echo "No Linux release bundle under $products" >&2; exit 1; }

  appdir="$(mktemp -d)/EngineStudio.AppDir"
  mkdir -p "$appdir/usr/bin" "$appdir/usr/share/applications" "$appdir/usr/share/icons/hicolor/256x256/apps"
  cp -R "$products"/* "$appdir/usr/bin/"
  # Prefer the flutter binary name from the bundle.
  bin="$(find "$appdir/usr/bin" -maxdepth 1 -type f -executable | head -n1)"
  [ -n "$bin" ] || { echo "No executable in Linux bundle" >&2; exit 1; }
  bin_name="$(basename "$bin")"
  cat >"$appdir/AppRun" <<EOF
#!/bin/sh
HERE="\$(dirname "\$(readlink -f "\$0")")"
exec "\$HERE/usr/bin/$bin_name" "\$@"
EOF
  chmod +x "$appdir/AppRun"
  cat >"$appdir/engine-studio.desktop" <<EOF
[Desktop Entry]
Name=Engine Studio
Exec=$bin_name
Icon=engine-studio
Type=Application
Categories=Development;
EOF
  cp "$appdir/engine-studio.desktop" "$appdir/usr/share/applications/"
  # Placeholder icon so AppDir validators don't reject a missing Icon=.
  : >"$appdir/engine-studio.png"
  cp "$appdir/engine-studio.png" "$appdir/usr/share/icons/hicolor/256x256/apps/"
else
  appdir="${APP_DIR:?APP_DIR must point at an AppDir when SKIP_FLUTTER_BUILD=1}"
  [ -d "$appdir" ] || { echo "APP_DIR is not a directory: $appdir" >&2; exit 1; }
fi

mkdir -p "$out"
archive="$out/EngineStudio-$version.AppDir.tar.gz"
tar -C "$(dirname "$appdir")" -czf "$archive" "$(basename "$appdir")"
shasum -a 256 "$archive" | awk '{print $1}' >"$archive.sha256"
echo "Wrote $archive"
echo "sha256 $(cat "$archive.sha256")"

if command -v appimagetool >/dev/null 2>&1; then
  img="$out/EngineStudio-$version.AppImage"
  ARCH=x86_64 appimagetool "$appdir" "$img"
  shasum -a 256 "$img" | awk '{print $1}' >"$img.sha256"
  echo "Wrote $img"
  echo "sha256 $(cat "$img.sha256")"
else
  echo "appimagetool not on PATH — skipped .AppImage (portable AppDir archive is enough for CI)."
fi
