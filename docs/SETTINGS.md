# 07 · Settings map

Every DataStore key of the native app (`constants/PreferenceKeys.kt`) and where it sits in
`lib/features/settings/settings_catalog.dart`; `test/app_test.dart` fails if a user-facing key
has no row. Keys marked *internal* are state, not settings.

New Flutter-only keys: `glassQuality` (FULL | FROSTED), `updateBetaChannel`,
`updateAutoDownload`, `updateWifiOnly`, `hydeSync*`, `ytmLastSync`.

Values live in shared_preferences (prefix `hyde.`), imported once from the
native DataStore file (docs/05).

## Shown vs hidden
The catalog lists every key so values survive the update and backups stay
compatible, but Settings only **shows** rows the Flutter app honours —
`supportedSettingKeys` at the end of `settings_catalog.dart`. Everything else
in the table below belongs to a native feature that was not ported
(docs/02 "Not ported") and is hidden. To surface a row, implement the
behaviour and add its key to that set.

Total keys: 236 · settings rows: 169 · internal: 67

| Key | Type | Flutter location |
|---|---|---|
| `enableDynamicIcon` | boolean | Appearance |
| `enableHighRefreshRate` | boolean | Appearance |
| `dynamicTheme` | boolean | Appearance |
| `selectedThemeColor` | int | — internal: internal UI state |
| `materialYou` | boolean | Appearance |
| `darkMode` | string | Appearance |
| `pureBlack` | boolean | Appearance |
| `pureBlackMiniPlayer` | boolean | Appearance |
| `appTheme` | string | Appearance |
| `density_scale_factor` | float | Appearance |
| `custom_density_scale_value` | float | — internal: internal UI state |
| `defaultOpenTab` | string | Appearance |
| `slimNavBar` | boolean | Appearance |
| `oldNavbarStyle` | boolean | Appearance |
| `gridItemSize` | string | Appearance |
| `sliderStyle` | string | Appearance |
| `SwipeToSong` | boolean | Appearance |
| `SwipeToRemoveSong` | boolean | Appearance |
| `useNewPlayerDesign` | boolean | Appearance |
| `useNewMiniPlayerDesign` | boolean | Appearance |
| `useSystemFont` | boolean | Appearance |
| `hidePlayerThumbnail` | boolean | Appearance |
| `cropAlbumArt` | boolean | Appearance |
| `seekExtraSeconds` | boolean | Playback |
| `pauseOnMute` | boolean | Playback |
| `resumeOnBluetoothConnect` | boolean | Playback |
| `keepScreenOn` | boolean | Playback |
| `developerMode` | boolean | App |
| `appLanguage` | string | App |
| `contentLanguage` | string | Content |
| `contentCountry` | string | Content |
| `enableKugou` | boolean | Lyrics |
| `enableLrclib` | boolean | Lyrics |
| `enableSimpMusic` | boolean | Lyrics |
| `enableBetterLyrics` | boolean | Lyrics |
| `enableLyricsPlus` | boolean | Lyrics |
| `hideExplicit` | boolean | Content |
| `hideVideoSongs` | boolean | Content |
| `hideYoutubeShorts` | boolean | Content |
| `proxyEnabled` | boolean | Content |
| `proxyUrl` | string | Content |
| `proxyType` | string | Content |
| `proxyUsername` | string | Content |
| `proxyPassword` | string | Content |
| `ytmSync` | boolean | YouTube Music Account |
| `checkForUpdates` | boolean | App |
| `updateNotifications` | boolean | App |
| `audioQuality` | string | Playback |
| `audioQualityPromptShown` | boolean | — internal: internal UI state |
| `studioEnhancerEnabled` | boolean | Audio Enhancer |
| `enhancerIntensity` | string | Audio Enhancer |
| `supabaseUserId` | string | — internal: session / credentials (engine-managed) |
| `supabaseEmail` | string | — internal: session / credentials (engine-managed) |
| `supabaseLoggedIn` | boolean | — internal: session / credentials (engine-managed) |
| `supabasePromptShown` | boolean | — internal: internal UI state |
| `lastSupabasePromptTime` | long | — internal: sync timestamps / last-seen markers |
| `equalizerPreset` | string | Audio Enhancer |
| `equalizerCustomMode` | boolean | Audio Enhancer |
| `enableOffload` | boolean | Playback |
| `virtualizerEnabled` | boolean | Audio Enhancer |
| `reverbEnabled` | boolean | Audio Enhancer |
| `dynamicsCompressorEnabled` | boolean | Audio Enhancer |
| `stereoWidth` | float | Audio Enhancer |
| `presenceBoost` | float | Audio Enhancer |
| `persistentQueue` | boolean | Playback |
| `persistentShuffleAcrossQueues` | boolean | Playback |
| `rememberShuffleAndRepeat` | boolean | Playback |
| `shuffleMode` | boolean | — internal: player runtime state |
| `smartShuffleEnabled` | boolean | Playback |
| `skipSilence` | boolean | Playback |
| `audioNormalization` | boolean | Playback |
| `autoLoadMore` | boolean | Playback |
| `disableLoadMoreWhenRepeatAll` | boolean | Playback |
| `autoDownloadOnLike` | boolean | Download |
| `similarContent` | boolean | Playback |
| `autoSkipNextOnError` | boolean | Playback |
| `stopMusicOnTaskClear` | boolean | Playback |
| `forceStopOnTaskClear` | boolean | Playback |
| `preventDuplicateTracksInQueue` | boolean | Playback |
| `crossfadeEnabled` | boolean | Playback |
| `crossfadeDurationFloat` | float | Playback |
| `crossfadeGapless` | boolean | Playback |
| `ttsAnnouncementEnabled` | boolean | Playback |
| `musicHapticsEnabled` | boolean | Playback |
| `pipEnabled` | boolean | Playback |
| `maxImageCacheSize` | int | Storage & Cache |
| `maxSongCacheSize` | int | Storage & Cache |
| `pauseListenHistory` | boolean | App |
| `pauseSearchHistory` | boolean | App |
| `disableScreenshot` | boolean | App |
| `chipSortType` | string | — internal: sort/filter/view state (owned by library screens) |
| `songSortType` | string | — internal: sort/filter/view state (owned by library screens) |
| `songSortDescending` | boolean | — internal: sort/filter/view state (owned by library screens) |
| `playlistSongSortType` | string | — internal: sort/filter/view state (owned by library screens) |
| `playlistSongSortDescending` | boolean | — internal: sort/filter/view state (owned by library screens) |
| `autoPlaylistSongSortType` | string | — internal: sort/filter/view state (owned by library screens) |
| `autoPlaylistSongSortDescending` | boolean | — internal: sort/filter/view state (owned by library screens) |
| `artistSortType` | string | — internal: sort/filter/view state (owned by library screens) |
| `artistSortDescending` | boolean | — internal: sort/filter/view state (owned by library screens) |
| `albumSortType` | string | — internal: sort/filter/view state (owned by library screens) |
| `albumSortDescending` | boolean | — internal: sort/filter/view state (owned by library screens) |
| `playlistSortType` | string | — internal: sort/filter/view state (owned by library screens) |
| `playlistSortDescending` | boolean | — internal: sort/filter/view state (owned by library screens) |
| `artistSongSortType` | string | — internal: sort/filter/view state (owned by library screens) |
| `artistSongSortDescending` | boolean | — internal: sort/filter/view state (owned by library screens) |
| `mixSortType` | string | — internal: sort/filter/view state (owned by library screens) |
| `songFilter` | string | — internal: sort/filter/view state (owned by library screens) |
| `artistFilter` | string | — internal: sort/filter/view state (owned by library screens) |
| `albumFilter` | string | — internal: sort/filter/view state (owned by library screens) |
| `last_like_song_sync` | long | — internal: sync timestamps / last-seen markers |
| `last_library_song_sync` | long | — internal: sync timestamps / last-seen markers |
| `last_album_sync` | long | — internal: sync timestamps / last-seen markers |
| `last_artist_sync` | long | — internal: sync timestamps / last-seen markers |
| `last_playlist_sync` | long | — internal: sync timestamps / last-seen markers |
| `artistViewType` | string | — internal: sort/filter/view state (owned by library screens) |
| `albumViewType` | string | — internal: sort/filter/view state (owned by library screens) |
| `playlistViewType` | string | — internal: sort/filter/view state (owned by library screens) |
| `playlistEditLock` | boolean | — internal: sort/filter/view state (owned by library screens) |
| `discover` | string | Content |
| `lyricsProvider` | string | Lyrics |
| `queueEditLock` | boolean | — internal: sort/filter/view state (owned by library screens) |
| `show_wrapped_card` | boolean | Appearance |
| `wrapped_seen` | boolean | — internal: sync timestamps / last-seen markers |
| `lastSeenVersion` | string | — internal: sync timestamps / last-seen markers |
| `randomizeHomeOrder` | boolean | Appearance |
| `show_liked_playlist` | boolean | Appearance |
| `show_downloaded_playlist` | boolean | Appearance |
| `show_top_playlist` | boolean | Appearance |
| `show_cached_playlist` | boolean | Appearance |
| `show_uploaded_playlist` | boolean | Appearance |
| `show_local_playlist` | boolean | Appearance |
| `enableGoogleCast` | boolean | Playback |
| `sponsorBlockEnabled` | boolean | Playback |
| `sponsorBlockCategories` | string | Playback |
| `anonymousAnalytics` | boolean | App |
| `scanPaths` | string | Files & Folders |
| `excludedScanPaths` | string | Files & Folders |
| `scannerSensitivity` | int | Local Library |
| `scannerStrictExt` | boolean | Local Library |
| `scannerStrictFilePaths` | boolean | Local Library |
| `lastLocalScan` | long | — internal: sync timestamps / last-seen markers |
| `lookupYtmArtists` | boolean | Local Library |
| `listenTogetherServerUrl` | string | Listen Together |
| `listenTogetherUsername` | string | Listen Together |
| `listenTogetherAutoApproval` | boolean | Listen Together |
| `listenTogetherSyncVolume` | boolean | Listen Together |
| `listenTogetherSmartResync` | boolean | Listen Together |
| `listenTogetherBlockedUsers` | string | — internal: session / credentials (engine-managed) |
| `listenTogetherInTopBar` | boolean | Listen Together |
| `listenTogetherSessionToken` | string | — internal: session / credentials (engine-managed) |
| `listenTogetherRoomCode` | string | — internal: session / credentials (engine-managed) |
| `listenTogetherUserId` | string | — internal: session / credentials (engine-managed) |
| `listenTogetherIsHost` | boolean | — internal: session / credentials (engine-managed) |
| `listenTogetherSessionTimestamp` | long | — internal: session / credentials (engine-managed) |
| `topSize` | string | Content |
| `historyDuration` | float | App |
| `player_buttons_style` | string | Appearance |
| `playerBackgroundStyle` | string | Appearance |
| `showLyrics` | boolean | — internal: player runtime state |
| `lyricsTextPosition` | string | Lyrics |
| `lyricsClick` | boolean | Lyrics |
| `lyricsScrollKey` | boolean | Lyrics |
| `tapAlbumArtForLyrics` | boolean | Appearance |
| `doubleTapToLike` | boolean | Appearance |
| `ambientModeDullBackground` | boolean | Appearance |
| `ambientModeSongAccent` | boolean | Appearance |
| `ambientModeLandscape` | boolean | Appearance |
| `lyricsRomanizeJapanese` | boolean | Romanization |
| `lyricsRomanizeKorean` | boolean | Romanization |
| `lyricsRomanizeRussian` | boolean | Romanization |
| `lyricsRomanizeUkrainian` | boolean | Romanization |
| `lyricsRomanizeSerbian` | boolean | Romanization |
| `lyricsRomanizeBulgarian` | boolean | Romanization |
| `lyricsRomanizeBelarusian` | boolean | Romanization |
| `lyricsRomanizeKyrgyz` | boolean | Romanization |
| `lyricsRomanizeMacedonian` | boolean | Romanization |
| `lyricsRomanizeCyrillicByLine` | boolean | Romanization |
| `translateLyrics` | boolean | Translation & AI |
| `openRouterApiKey` | string | Translation & AI |
| `aiProvider` | string | Translation & AI |
| `openRouterBaseUrl` | string | Translation & AI |
| `openRouterModel` | string | Translation & AI |
| `autoTranslateLyrics` | boolean | Translation & AI |
| `autoTranslateLyricsMismatch` | boolean | Translation & AI |
| `translateMode` | string | Translation & AI |
| `translateLanguage` | string | Translation & AI |
| `deeplApiKey` | string | Translation & AI |
| `deeplFormality` | string | Translation & AI |
| `lyricsGlowEffect` | boolean | Lyrics |
| `appleMusicLyricsBlur` | boolean | Lyrics |
| `thumbnailCornerRadius` | float | Appearance |
| `canvasThumbnailAnimation` | boolean | Appearance |
| `lyricsAnimationStyle` | string | Lyrics |
| `lyricsTextSize` | float | Lyrics |
| `lyricsLineSpacing` | float | Lyrics |
| `lyricsProviderOrder` | string | Lyrics |
| `discordToken` | string | — internal: session / credentials (engine-managed) |
| `discordInfoDismissed` | boolean | — internal: internal UI state |
| `discordUsername` | string | — internal: session / credentials (engine-managed) |
| `discordName` | string | — internal: session / credentials (engine-managed) |
| `discordRPCEnable` | boolean | Discord |
| `discordUseDetails` | boolean | Discord |
| `discordAvatar` | string | — internal: session / credentials (engine-managed) |
| `discordStatus` | string | Discord |
| `discordButton1Text` | string | Discord |
| `discordButton1Visible` | boolean | Discord |
| `discordButton2Text` | string | Discord |
| `discordButton2Visible` | boolean | Discord |
| `discordActivityType` | string | Discord |
| `discordActivityName` | string | Discord |
| `discordAdvancedMode` | boolean | Discord |
| `lastfmSession` | string | — internal: sync timestamps / last-seen markers |
| `lastfmUsername` | string | — internal: sync timestamps / last-seen markers |
| `lastfmScrobblingEnable` | boolean | Last.fm |
| `lastfmUseNowPlaying` | boolean | Last.fm |
| `lastfmUseSendLikes` | boolean | Last.fm |
| `scrobbleDelayPercent` | float | Last.fm |
| `scrobbleMinSongDuration` | int | Last.fm |
| `scrobbleDelaySeconds` | int | Last.fm |
| `podcastFilter` | string | — internal: sort/filter/view state (owned by library screens) |
| `playerVolume` | float | — internal: player runtime state |
| `sleepTimerDefault` | float | Playback |
| `repeatMode` | int | — internal: player runtime state |
| `searchSource` | string | — internal: player runtime state |
| `swipeThumbnail` | boolean | Appearance |
| `swipeSensitivity` | float | Appearance |
| `visitorData` | string | — internal: session / credentials (engine-managed) |
| `dataSyncId` | string | — internal: session / credentials (engine-managed) |
| `innerTubeCookie` | string | — internal: session / credentials (engine-managed) |
| `accountName` | string | — internal: session / credentials (engine-managed) |
| `accountEmail` | string | — internal: session / credentials (engine-managed) |
| `accountChannelHandle` | string | — internal: session / credentials (engine-managed) |
| `activeAccountId` | string | — internal: session / credentials (engine-managed) |
| `useLoginForBrowse` | boolean | YouTube Music Account |
| `lastImportantNoticeVersion` | string | — internal: sync timestamps / last-seen markers |
| `show_find_in_navbar` | boolean | Appearance |
