# Building Hyde Music for desktop

## Requirements

- Flutter 3.47 (stable) — `flutter --version`
- **Linux**: clang, cmake, ninja, pkg-config, GTK 3 headers and **libmpv**
  ```bash
  # Ubuntu / Debian
  sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev libmpv-dev
  # Fedora
  sudo dnf install clang cmake ninja-build pkgconf gtk3-devel mpv-libs-devel
  # Arch
  sudo pacman -S clang cmake ninja pkgconf gtk3 mpv
  ```
- **Windows**: Visual Studio 2022 with *Desktop development with C++*. libmpv is
  downloaded automatically by `media_kit_libs_windows_audio` during the build.
  For the installer: [Inno Setup 6](https://jrsoftware.org/isdl.php).

Windows builds have to be made on Windows (Flutter can't cross-compile); CI
does this on `windows-2022`.

### libmpv without root (Linux)

If you can't install packages, unpack libmpv locally and the app and the
AppImage script will pick it up from `.deps/root/usr/lib64`:

```bash
mkdir -p .deps/rpms .deps/root && cd .deps/rpms
dnf download --resolve --arch x86_64 --arch noarch mpv-libs   # Fedora
cd ../root && for r in ../rpms/*.rpm; do rpm2cpio "$r" | cpio -idm --quiet; done
cd ../.. && export LD_LIBRARY_PATH=$PWD/.deps/root/usr/lib64
```

## Run

```bash
flutter pub get
flutter run -d linux            # or -d windows
```

Demo data (no network, no audio): `flutter run -d linux --dart-define=HYDE_ENGINE=mock`.

Developer launch options (environment variables), handy for testing and screenshots:

| Variable | Effect |
|---|---|
| `HYDE_AUTOPLAY="song"` | Search, play the first result at 20 % volume and log playback to stdout |
| `HYDE_OPEN=playlist:<id>` | Open a playlist (also `album:<id>`, `artist:<id>`) |
| `HYDE_SEARCH="query"` | Open Search with a query |
| `HYDE_PANE=lyrics` | Open the lyrics (or `queue`) view after start |

## Test

```bash
flutter analyze
flutter test --exclude-tags live,screenshots     # unit + widget tests
flutter test --tags live                         # real YouTube Music / lyrics calls
flutter test test/screenshots --update-goldens   # PNGs of every screen → test/screenshots/out/
```

## Package

### Linux
```bash
packaging/linux/build-appimage.sh
```
Produces in `dist/`:
- `HydeMusic-<v>-linux-x86_64.AppImage` — bundles libmpv and its codec libraries;
  base system libraries (glibc, GPU, audio server, GTK) come from the user's distro.
- `HydeMusic-<v>-linux-x86_64.tar.gz` — the Flutter bundle; uses the system libmpv.

An AppImage only runs on distros with a glibc at least as new as the build
machine's, which is why releases are built on Ubuntu 22.04.

### Windows
```powershell
flutter build windows --release
& "${env:ProgramFiles(x86)}\Inno Setup 6\iscc.exe" /DAppVersion=1.0.0 packaging\windows\hyde-music.iss
```
Produces `dist\HydeMusic-<v>-windows-x64-Setup.exe`.

## Release

1. Bump `version:` in `pubspec.yaml` and add `docs/release-notes/<version>.md`
   plus a `CHANGELOG.md` entry.
2. Tag and push: `git tag v1.0.1 && git push origin main v1.0.1`.
3. GitHub Actions (`.github/workflows/build.yml`) tests, builds Linux and
   Windows, and publishes the release with `SHA256SUMS`. Installed apps find
   it through the in-app updater (`lib/engine/dart/updater.dart`), which
   reads `Hyde-OpenSource/Hyde-Music-Desktop`.
