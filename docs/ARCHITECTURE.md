# Architecture

```
┌──────────────────────────── Flutter UI (Cupertino + Liquid Glass) ───────────────────────────┐
│ DesktopShell: glass sidebar · per-section navigators · PlayerBar · DesktopNowPlaying · keys  │
│ features/: home, search, library, find, player, settings, more                               │
└──────────────────────────────────────┬───────────────────────────────────────────────────────┘
                                       │  HydeEngine (lib/engine/hyde_engine.dart) — the only API
┌──────────────────────────────────────┴───────────────────────────────────────────────────────┐
│ DartEngine (lib/engine/dart)                                                                  │
│  innertube.dart / youtube.dart   YouTube Music InnerTube client (home, search, pages, radio)  │
│  stream_resolver.dart            audio stream URLs, ranged reads (youtube_audio_source.dart)  │
│  player.dart + smart_shuffle.dart  queue, shuffle / AI Shuffle, radio, SponsorBlock           │
│  database.dart                   song.db (SQLite via sqflite_common_ffi on desktop)           │
│  lyrics.dart, downloader.dart, updater.dart, discord.dart, lastfm.dart, listen_together.dart │
└──────────────────────────────────────┬───────────────────────────────────────────────────────┘
                     just_audio ──► just_audio_media_kit ──► libmpv (audio output)
```

## Platform choices

| Concern | Android app | Desktop |
|---|---|---|
| Audio | just_audio (ExoPlayer) + audio_service | just_audio_media_kit → libmpv; no audio_service |
| Database | sqflite | sqflite_common_ffi (bundled SQLite) |
| Sign-in | in-app webview | paste the music.youtube.com cookie (no embeddable webview) |
| Updates | APK install | Windows: Inno Setup installer `/SILENT`; Linux: swap the AppImage |
| Layout | floating tab bar + mini player | sidebar + full-width player bar + Now Playing overlay |

Mobile-only features (system equaliser, "open by default", local media
scan, Nearby sync) are hidden in Settings through
`_unsupportedActions` / `supportedSettingKeys` in `settings_catalog.dart`.

## Rendering and heat

The Liquid Glass lenses are Impeller shaders that re-render with every frame,
so the app keeps the frame count low: no idle tickers, timers instead of
per-vsync tickers for the lyrics clock and the glow background, and artwork
decoded at the size it is shown.

## libmpv lookup (Linux)

`main.dart` passes a bundled `lib/libmpv.so.{2,1}` (AppImage or portable
folder) to `JustAudioMediaKit.ensureInitialized`, and otherwise falls back to
the system library.
