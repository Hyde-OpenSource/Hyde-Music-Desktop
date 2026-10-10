# Changelog

## 1.0.0 — 2026-10-10

First release for Windows and Linux.

### Added
- Desktop shell: Liquid Glass sidebar (search, sections, playlists), full-width glass player bar, Now Playing with lyrics / queue beside the cover.
- AI Shuffle (player bar, queue, playlists, albums, Suggested Songs) using the same algorithm as Android 6.0.
- Suggested Songs under playlists, with + to add on your own playlists.
- Reload button and F5 on Home.
- Keyboard and media-key shortcuts.
- Desktop playlist / album header with the cover beside the title.
- Cookie sign-in for YouTube Music.
- Desktop updater (Inno Setup installer on Windows, AppImage swap on Linux).
- Packaging: AppImage (bundled libmpv), tar.gz, Windows installer and portable zip; GitHub Actions builds and releases on `v*` tags.

### Changed
- Audio through libmpv (just_audio_media_kit); library database through SQLite FFI.
- Mobile-only settings (system equaliser, open-by-default, local scan, Nearby sync, launch tab, swipe gestures) are hidden.

### Fixed
- Home failed on a fresh library ("Cannot modify an unmodifiable list").
