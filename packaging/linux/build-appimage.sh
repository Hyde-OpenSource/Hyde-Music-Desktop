#!/usr/bin/env bash
# Builds Hyde Music for Linux and packages it as:
#   dist/HydeMusic-<version>-linux-x86_64.AppImage   (self-contained: bundles libmpv + codecs)
#   dist/HydeMusic-<version>-linux-x86_64.tar.gz     (needs the system libmpv: libmpv2 / mpv-libs)
#
# Needs: flutter, libmpv (system, or extracted into .deps/root/usr/lib64 — see docs/BUILDING.md),
# and network access the first time (downloads appimagetool).
# Release builds are made by CI on Ubuntu 22.04, so they run on any distro
# with glibc 2.35 or newer; a local build only runs on distros as new as yours.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
VERSION="$(grep -m1 '^version:' pubspec.yaml | sed -E 's/version: *([^+]+).*/\1/')"
DIST="$ROOT/dist"
APPDIR="$ROOT/build/AppDir"
TOOLS="$ROOT/.deps/tools"
mkdir -p "$DIST" "$TOOLS"

echo "== Building Hyde Music $VERSION"
flutter build linux --release
BUNDLE="$ROOT/build/linux/x64/release/bundle"

# Where to find libmpv: a local extract (no root needed) or the system.
EXTRA_LIBS="$ROOT/.deps/root/usr/lib64"
export LD_LIBRARY_PATH="${EXTRA_LIBS}${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
# libmpv.so.2 (mpv ≥ 0.35) or libmpv.so.1 (Ubuntu 22.04's mpv 0.34).
LIBMPV="$(ldconfig -p | awk '/libmpv\.so\.[12] / {print $NF; exit}')"
[[ -f "$EXTRA_LIBS/libmpv.so.2" ]] && LIBMPV="$EXTRA_LIBS/libmpv.so.2"
[[ -n "$LIBMPV" && -f "$LIBMPV" ]] || { echo "libmpv not found (install libmpv2 / libmpv1 / mpv-libs)"; exit 1; }
LIBMPV_SONAME="$(objdump -p "$LIBMPV" | awk '/SONAME/ {print $2}')"

echo "== tar.gz (system libmpv)"
TAR="$DIST/HydeMusic-$VERSION-linux-x86_64.tar.gz"
rm -rf "$ROOT/build/tar" && mkdir -p "$ROOT/build/tar/HydeMusic"
cp -a "$BUNDLE/." "$ROOT/build/tar/HydeMusic/"
cp packaging/linux/tech.hydeos.HydeMusic.desktop packaging/icons/hyde-music-256.png "$ROOT/build/tar/HydeMusic/"
tar -C "$ROOT/build/tar" -czf "$TAR" HydeMusic

echo "== AppImage (bundled libmpv)"
rm -rf "$APPDIR" && mkdir -p "$APPDIR"
cp -a "$BUNDLE/." "$APPDIR/"
cp packaging/linux/tech.hydeos.HydeMusic.desktop "$APPDIR/"
cp packaging/icons/hyde-music-256.png "$APPDIR/tech.hydeos.HydeMusic.png"
ln -sf tech.hydeos.HydeMusic.png "$APPDIR/.DirIcon"

# libmpv and every library it pulls in, except the base system ones that
# must come from the user's distro (glibc, GPU drivers, audio server, GTK…).
EXCLUDE='^(ld-linux|libc\.|libm\.|libdl\.|libpthread|librt\.|libresolv|libutil|libgcc_s|libstdc\+\+|libGL|libEGL|libGLX|libGLdispatch|libOpenGL|libdrm|libgbm|libvulkan|libX11|libXext\.|libXrender|libXfixes|libXi\.|libXrandr|libXcursor|libXinerama|libXau|libXdmcp|libXcomposite|libXdamage|libxcb|libxkb|libwayland|libasound|libpulse|libpipewire|libjack|libdbus|libsystemd|libudev|libcap\.|libfontconfig|libfreetype|libharfbuzz|libfribidi|libglib|libgio|libgobject|libgmodule|libgthread|libgtk|libgdk|libcairo|libpango|libatk|libatspi|libepoxy|libz\.so|libexpat|libuuid|libblkid|libmount|libselinux|libpcre|libffi|libgnutls|libnettle|libhogweed|libgmp|libp11-kit|libtasn1|libidn2|libunistring|libcrypto|libssl|libbz2|liblzma|libzstd|libsqlite3)'
cp -L "$LIBMPV" "$APPDIR/lib/$LIBMPV_SONAME"
ldd "$LIBMPV" | awk '/=> \// {print $3}' | while read -r lib; do
  name="$(basename "$lib")"
  [[ "$name" =~ $EXCLUDE ]] && continue
  cp -Ln "$lib" "$APPDIR/lib/$name"
done

cat > "$APPDIR/AppRun" <<'APPRUN'
#!/bin/sh
HERE="$(dirname "$(readlink -f "$0")")"
export APPDIR="${APPDIR:-$HERE}"
export LD_LIBRARY_PATH="$HERE/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
exec "$HERE/hyde-music" "$@"
APPRUN
chmod +x "$APPDIR/AppRun"

APPIMAGETOOL="$TOOLS/appimagetool-x86_64.AppImage"
if [[ ! -x "$APPIMAGETOOL" ]]; then
  curl -fL -o "$APPIMAGETOOL" \
    "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage"
  chmod +x "$APPIMAGETOOL"
fi
OUT="$DIST/HydeMusic-$VERSION-linux-x86_64.AppImage"
ARCH=x86_64 "$APPIMAGETOOL" --appimage-extract-and-run --no-appstream "$APPDIR" "$OUT"

(cd "$DIST" && sha256sum "$(basename "$OUT")" "$(basename "$TAR")" > "SHA256SUMS-linux.txt")
echo "== Done"
ls -lh "$DIST"
