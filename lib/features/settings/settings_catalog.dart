import 'package:flutter/cupertino.dart';

import '../../core/theme/hyde_theme.dart';

/// Every user-facing setting of the native app, declared as data.
///
/// Keys are the exact DataStore names from
/// app/src/main/kotlin/iad1tya/echo/music/constants/PreferenceKeys.kt, so the
/// existing user's values are read as-is after the upgrade. Internal state keys
/// (sort orders, view types, sync timestamps, session tokens…) are not shown
/// here but are honoured by the screens that own them — see
/// docs/07_SETTINGS_MAP.md for the full 236-key audit.
///
/// Grouping follows the reference Settings screenshot.

sealed class SettingItem {
  const SettingItem(this.title, {this.subtitle});
  final String title;
  final String? subtitle;
}

class ToggleSetting extends SettingItem {
  const ToggleSetting(this.key, super.title, {super.subtitle, this.defaultValue = false});
  final String key;
  final bool defaultValue;
}

class ChoiceSetting extends SettingItem {
  const ChoiceSetting(this.key, super.title, this.options, {super.subtitle, required this.defaultValue});
  final String key;
  final List<(String value, String label)> options;
  final String defaultValue;
}

class SliderSetting extends SettingItem {
  const SliderSetting(
    this.key,
    super.title, {
    super.subtitle,
    required this.min,
    required this.max,
    required this.defaultValue,
    this.divisions,
    this.unit = '',
    this.isInt = false,
  });
  final String key;
  final double min;
  final double max;
  final double defaultValue;
  final int? divisions;
  final String unit;

  /// Stored as int in DataStore (intPreferencesKey).
  final bool isInt;
}

class TextSetting extends SettingItem {
  const TextSetting(this.key, super.title, {super.subtitle, this.placeholder = '', this.secret = false});
  final String key;
  final String placeholder;
  final bool secret;
}

/// Runs an engine action (clear cache, backup, login…).
class ActionSetting extends SettingItem {
  const ActionSetting(this.action, super.title, {super.subtitle, this.destructive = false, this.confirm});
  final String action;
  final bool destructive;

  /// When set, shows a confirmation with this message first.
  final String? confirm;
}

/// Where each [ActionSetting] goes: `flutter:<screen>`, `feature:<native call>`
/// (optionally `?<kind>`), `dialog:<name>`, `system:<intent>`, `import:<format>`.
const settingActionTargets = <String, String>{
  'account.login': 'flutter:account',
  'account.tokenLogin': 'flutter:account',
  'account.logout': 'flutter:account',
  'discord.login': 'flutter:discordLogin',
  'discord.logout': 'feature:discord.logout',
  'lastfm.login': 'dialog:lastfm',
  'lastfm.logout': 'feature:lastfm.logout',
  'listenTogether.open': 'flutter:listenTogether',
  'listenTogether.blocked': 'flutter:listenTogether',
  'listenTogether.logs': 'flutter:logs',
  'supabase.login': 'flutter:hydesync',
  'supabase.syncNow': 'flutter:hydesync',
  'supabase.logout': 'flutter:hydesync',
  'nearbySync.open': 'flutter:nearby',
  'local.scan': 'flutter:local',
  'local.grantPermission': 'feature:local.scan',
  'audio.systemEqualizer': 'system:equalizer',
  'download.manage': 'flutter:downloads',
  'download.clearAll': 'feature:storage.clear?download',
  'app.defaultLinks': 'system:defaultLinks',
  'app.checkNow': 'flutter:updates',
  'privacy.clearListenHistory': 'feature:privacy.clearListenHistory',
  'privacy.clearSearchHistory': 'feature:privacy.clearSearchHistory',
  'storage.clearSongCache': 'feature:storage.clear?song',
  'storage.clearImageCache': 'feature:storage.clear?image',
  'backup.create': 'feature:backup.create',
  'backup.restore': 'feature:backup.restore',
  'import.spotify': 'flutter:spotify',
  'import.csv': 'import:csv',
  'import.online': 'import:m3u',
  'logs.crash': 'flutter:logs',
  'logs.listenTogether': 'flutter:logs',
  'logs.share': 'flutter:logs',
  'support.patreon': 'flutter:support',
  'support.upi': 'flutter:support',
  'support.crypto': 'flutter:support',
  'about.website': 'flutter:about',
  'about.github': 'flutter:about',
  'about.telegram': 'flutter:about',
  'about.discord': 'flutter:about',
  'about.privacy': 'flutter:about',
  'about.contact': 'flutter:about',
  'about.licenses': 'flutter:about',
};

/// Read-only value row (diagnostics).
class InfoSetting extends SettingItem {
  const InfoSetting(this.info, super.title, {super.subtitle});
  final String info;
}

class PageLink extends SettingItem {
  const PageLink(this.page, {super.subtitle}) : super('');
  final SettingsPage page;
  @override
  String get title => page.title;
}

class SettingsSection {
  const SettingsSection(this.items, {this.header, this.footer});
  final String? header;
  final String? footer;
  final List<SettingItem> items;
}

class SettingsPage {
  const SettingsPage({
    required this.id,
    required this.title,
    required this.icon,
    required this.color,
    required this.sections,
  });
  final String id;
  final String title;
  final IconData icon;
  final Color color;
  final List<SettingsSection> sections;
}

// ── Option lists (enum values identical to the Kotlin enums) ───────────────

const _onOffAuto = [('ON', 'On'), ('OFF', 'Off'), ('AUTO', 'Follow system')];
const _audioQuality = [('AUTO', 'Auto (dynamic)'), ('BEST_AVAILABLE', 'Best available'), ('DATA_SAVER', 'Data saver')];
const _lyricsProviders = [
  ('LRCLIB', 'LRCLIB'),
  ('SIMPMUSIC', 'SimpMusic'),
  ('KUGOU', 'KuGou'),
  ('BETTERLYRICS', 'BetterLyrics'),
  ('LYRICSPLUS', 'LyricsPlus'),
];

// ── Pages ───────────────────────────────────────────────────────────────────

const accountPage = SettingsPage(
  id: 'account',
  title: 'Account',
  icon: CupertinoIcons.person_crop_circle,
  color: HydeColors.accent,
  sections: [
    SettingsSection([
      ActionSetting('account.login', 'Sign in / switch account', subtitle: 'Multiple accounts supported'),
      ActionSetting('account.tokenLogin', 'Advanced login (token)'),
      ActionSetting('account.logout', 'Sign out', destructive: true, confirm: 'Sign out of your account?'),
    ]),
    SettingsSection([
      ToggleSetting('ytmSync', 'Sync your library', subtitle: 'Likes, library, playlists', defaultValue: true),
      ToggleSetting('useLoginForBrowse', 'Use account for browsing', subtitle: 'Personalised Home and recommendations'),
    ]),
  ],
);

const discordPage = SettingsPage(
  id: 'discord',
  title: 'Discord',
  icon: CupertinoIcons.game_controller,
  color: HydeColors.indigo,
  sections: [
    SettingsSection([
      InfoSetting('discord.user', 'Account'),
      ActionSetting('discord.login', 'Log in to Discord'),
      ActionSetting('discord.logout', 'Log out', destructive: true),
    ]),
    SettingsSection(header: 'Rich presence', [
      ToggleSetting('discordRPCEnable', 'Show what I’m listening to'),
      ToggleSetting('discordUseDetails', 'Show song details'),
      ChoiceSetting('discordStatus', 'Status', [
        ('online', 'Online'),
        ('idle', 'Idle'),
        ('dnd', 'Do not disturb'),
      ], defaultValue: 'online'),
      ChoiceSetting('discordActivityType', 'Activity type', [
        ('listening', 'Listening'),
        ('playing', 'Playing'),
        ('watching', 'Watching'),
        ('competing', 'Competing'),
      ], defaultValue: 'listening'),
      TextSetting('discordActivityName', 'Activity name', placeholder: 'Hyde Music'),
      ToggleSetting('discordAdvancedMode', 'Advanced mode', subtitle: 'Custom buttons and text variables'),
    ]),
    SettingsSection(header: 'Buttons', footer: 'Variables: {song}, {artist}, {album}, {url}', [
      ToggleSetting('discordButton1Visible', 'Show button 1', defaultValue: true),
      TextSetting('discordButton1Text', 'Button 1 text', placeholder: 'Listen on Hyde Music'),
      ToggleSetting('discordButton2Visible', 'Show button 2', defaultValue: true),
      TextSetting('discordButton2Text', 'Button 2 text', placeholder: 'Visit Hyde Music'),
    ]),
  ],
);

const lastFmPage = SettingsPage(
  id: 'lastfm',
  title: 'Last.fm',
  icon: CupertinoIcons.dot_radiowaves_left_right,
  color: Color(0xFFD51007),
  sections: [
    SettingsSection([
      InfoSetting('lastfm.user', 'Account'),
      ActionSetting('lastfm.login', 'Log in to Last.fm'),
      ActionSetting('lastfm.logout', 'Log out', destructive: true),
    ]),
    SettingsSection(header: 'Scrobbling', [
      ToggleSetting('lastfmScrobblingEnable', 'Enable scrobbling'),
      ToggleSetting('lastfmUseNowPlaying', 'Update “Now Playing”'),
      ToggleSetting('lastfmUseSendLikes', 'Send likes as loved tracks'),
      SliderSetting(
        'scrobbleDelayPercent',
        'Scrobble after % played',
        min: 0.3,
        max: 0.95,
        defaultValue: 0.5,
        divisions: 13,
      ),
      SliderSetting(
        'scrobbleMinSongDuration',
        'Minimum track length',
        min: 10,
        max: 120,
        defaultValue: 30,
        unit: 's',
        isInt: true,
      ),
      SliderSetting('scrobbleDelaySeconds', 'Or after', min: 30, max: 600, defaultValue: 180, unit: 's', isInt: true),
    ]),
  ],
);

const listenTogetherPage = SettingsPage(
  id: 'listentogether',
  title: 'Listen Together',
  icon: CupertinoIcons.person_2,
  color: HydeColors.pink,
  sections: [
    SettingsSection([ActionSetting('listenTogether.open', 'Open Listen Together', subtitle: 'Create or join a room')]),
    SettingsSection(header: 'Profile & server', [
      TextSetting('listenTogetherUsername', 'Username'),
      TextSetting('listenTogetherServerUrl', 'Custom server URL', placeholder: 'Default server'),
    ]),
    SettingsSection(header: 'Room', [
      ToggleSetting('listenTogetherAutoApproval', 'Auto-approve join requests'),
      ToggleSetting('listenTogetherSyncVolume', 'Sync volume'),
      ToggleSetting('listenTogetherSmartResync', 'Smart resync', defaultValue: true),
      ToggleSetting('listenTogetherInTopBar', 'Show in top bar'),
      ActionSetting('listenTogether.blocked', 'Blocked users'),
      ActionSetting('listenTogether.logs', 'View logs'),
    ]),
  ],
);

const hydeSyncPage = SettingsPage(
  id: 'hydesync',
  title: 'Hyde Sync',
  icon: CupertinoIcons.cloud_download,
  color: HydeColors.cyan,
  sections: [
    SettingsSection(footer: 'Cloud backup of library and playlists across devices.', [
      ActionSetting('supabase.login', 'Sign in to Hyde Sync'),
      ActionSetting('supabase.syncNow', 'Sync now'),
      ActionSetting('supabase.logout', 'Sign out', destructive: true),
    ]),
    SettingsSection(header: 'Nearby', footer: 'Play in sync with devices on the same Wi-Fi.', [
      ActionSetting('nearbySync.open', 'Nearby Sync'),
    ]),
  ],
);

const integrationsPage = SettingsPage(
  id: 'integrations',
  title: 'Integrations',
  icon: CupertinoIcons.square_grid_2x2,
  color: HydeColors.teal,
  sections: [
    SettingsSection([
      PageLink(accountPage),
      PageLink(hydeSyncPage),
      PageLink(listenTogetherPage),
      PageLink(discordPage),
      PageLink(lastFmPage),
    ]),
  ],
);

const appearancePage = SettingsPage(
  id: 'appearance',
  title: 'Appearance',
  icon: CupertinoIcons.paintbrush,
  color: HydeColors.purple,
  sections: [
    SettingsSection(header: 'Theme', [
      ChoiceSetting('darkMode', 'Appearance', _onOffAuto, defaultValue: 'AUTO'),
      ToggleSetting('pureBlack', 'Pure black'),
      ToggleSetting('pureBlackMiniPlayer', 'Pure black mini player'),
      ToggleSetting('dynamicTheme', 'Colour from artwork', defaultValue: true),
      ToggleSetting('materialYou', 'Colour from wallpaper', subtitle: 'Android 12+'),
      ChoiceSetting('appTheme', 'Background theme', [
        ('DEFAULT', 'Default'),
        ('MOUNTAINS', 'Mountains'),
      ], defaultValue: 'DEFAULT'),
      ToggleSetting('enableDynamicIcon', 'Dynamic app icon'),
      ToggleSetting('useSystemFont', 'Use system font'),
    ]),
    SettingsSection(header: 'Liquid Glass', footer: 'Frosted uses blur only and saves battery on older phones.', [
      ChoiceSetting('glassQuality', 'Glass quality', [
        ('FULL', 'Full (refraction)'),
        ('FROSTED', 'Frosted'),
      ], defaultValue: 'FULL'),
      InfoSetting('glass.renderer', 'Renderer'),
      InfoSetting('engine', 'Playback engine'),
    ]),
    SettingsSection(header: 'Player', [
      ChoiceSetting('playerBackgroundStyle', 'Player background', [
        ('DEFAULT', 'Default'),
        ('GRADIENT', 'Gradient'),
        ('BLUR', 'Blurred artwork'),
        ('GLOW_ANIMATED', 'Animated glow'),
      ], defaultValue: 'GRADIENT'),
      ChoiceSetting('player_buttons_style', 'Player buttons', [
        ('DEFAULT', 'Default'),
        ('SECONDARY', 'Secondary'),
        ('TERTIARY', 'Tertiary'),
      ], defaultValue: 'DEFAULT'),
      ChoiceSetting('sliderStyle', 'Seek bar', [
        ('DEFAULT', 'Default'),
        ('SQUIGGLY', 'Squiggly'),
        ('SLIM', 'Slim'),
      ], defaultValue: 'DEFAULT'),
      SliderSetting('thumbnailCornerRadius', 'Artwork corner radius', min: 0, max: 40, defaultValue: 14, unit: 'pt'),
      ToggleSetting('hidePlayerThumbnail', 'Hide artwork'),
      ToggleSetting('cropAlbumArt', 'Crop album art to square'),
      ToggleSetting('canvasThumbnailAnimation', 'Animated canvas artwork'),
      ToggleSetting('swipeThumbnail', 'Swipe artwork to change song', defaultValue: true),
      SliderSetting('swipeSensitivity', 'Swipe sensitivity', min: 0.1, max: 1, defaultValue: 0.73),
      ToggleSetting('tapAlbumArtForLyrics', 'Tap artwork for lyrics', defaultValue: true),
      ToggleSetting('doubleTapToLike', 'Double-tap artwork to like'),
      ToggleSetting('useNewPlayerDesign', 'New player design', defaultValue: true),
      ToggleSetting('useNewMiniPlayerDesign', 'New mini player design', defaultValue: true),
    ]),
    SettingsSection(header: 'Ambient mode', [
      ToggleSetting('ambientModeDullBackground', 'Dim background'),
      ToggleSetting('ambientModeSongAccent', 'Use song accent colour'),
      ToggleSetting('ambientModeLandscape', 'Landscape'),
    ]),
    SettingsSection(header: 'Navigation & layout', [
      ChoiceSetting('defaultOpenTab', 'Open on launch', [
        ('HOME', 'Home'),
        ('LIBRARY', 'Library'),
        ('SEARCH', 'Search'),
        ('FIND', 'Find'),
      ], defaultValue: 'HOME'),
      ToggleSetting('show_find_in_navbar', 'Show Find tab', defaultValue: true),
      ToggleSetting('slimNavBar', 'Slim tab bar'),
      ToggleSetting('oldNavbarStyle', 'Classic tab bar'),
      ChoiceSetting('gridItemSize', 'Grid size', [('BIG', 'Big'), ('SMALL', 'Small')], defaultValue: 'BIG'),
      ChoiceSetting('density_scale_factor', 'Display density', [
        ('NATIVE', 'Native'),
        ('SLIGHTLY_COMPACT', 'Slightly compact'),
        ('COMPACT', 'Compact'),
        ('VERY_COMPACT', 'Very compact'),
        ('ULTRA_COMPACT', 'Ultra compact'),
      ], defaultValue: 'NATIVE'),
      ToggleSetting('enableHighRefreshRate', 'High refresh rate', defaultValue: true),
      ToggleSetting('randomizeHomeOrder', 'Shuffle Home sections'),
      ToggleSetting('show_wrapped_card', 'Show Wrapped card', defaultValue: true),
    ]),
    SettingsSection(header: 'Gestures', [
      ToggleSetting('SwipeToSong', 'Swipe mini player to skip', defaultValue: true),
      ToggleSetting('SwipeToRemoveSong', 'Swipe to remove from playlist'),
    ]),
    SettingsSection(header: 'Library chips', [
      ToggleSetting('show_liked_playlist', 'Liked', defaultValue: true),
      ToggleSetting('show_downloaded_playlist', 'Downloaded', defaultValue: true),
      ToggleSetting('show_top_playlist', 'My top', defaultValue: true),
      ToggleSetting('show_cached_playlist', 'Cached', defaultValue: true),
      ToggleSetting('show_uploaded_playlist', 'Uploaded', defaultValue: true),
      ToggleSetting('show_local_playlist', 'Local', defaultValue: true),
    ]),
  ],
);

const localLibraryPage = SettingsPage(
  id: 'localLibrary',
  title: 'Local Library',
  icon: CupertinoIcons.music_note_list,
  color: HydeColors.blue,
  sections: [
    SettingsSection([
      ActionSetting('local.scan', 'Scan now'),
      SliderSetting(
        'scannerSensitivity',
        'Matching sensitivity',
        min: 0,
        max: 100,
        defaultValue: 80,
        unit: '%',
        isInt: true,
      ),
      ToggleSetting('scannerStrictExt', 'Only known audio extensions'),
      ToggleSetting('scannerStrictFilePaths', 'Strict file paths'),
      ToggleSetting('lookupYtmArtists', 'Match local artists online'),
    ]),
  ],
);

const contentPage = SettingsPage(
  id: 'content',
  title: 'Content',
  icon: CupertinoIcons.tag,
  color: HydeColors.yellow,
  sections: [
    SettingsSection(header: 'Region', [
      TextSetting('contentLanguage', 'Content language', placeholder: 'System default'),
      TextSetting('contentCountry', 'Content country', placeholder: 'System default'),
    ]),
    SettingsSection(header: 'Filters', [
      ToggleSetting('hideExplicit', 'Hide explicit content'),
      ToggleSetting('hideVideoSongs', 'Hide video songs'),
      ToggleSetting('hideYoutubeShorts', 'Hide short clips'),
    ]),
    SettingsSection(header: 'Home', [
      ChoiceSetting('discover', 'Quick picks source', [
        ('QUICK_PICKS', 'Quick picks'),
        ('LAST_LISTEN', 'Last listened'),
      ], defaultValue: 'QUICK_PICKS'),
      ChoiceSetting('topSize', '“My top” length', [('25', '25'), ('50', '50'), ('100', '100')], defaultValue: '50'),
    ]),
    SettingsSection(header: 'Proxy', [
      ToggleSetting('proxyEnabled', 'Use proxy'),
      ChoiceSetting('proxyType', 'Type', [('HTTP', 'HTTP'), ('SOCKS', 'SOCKS')], defaultValue: 'HTTP'),
      TextSetting('proxyUrl', 'Address', placeholder: 'host:port'),
      TextSetting('proxyUsername', 'Username'),
      TextSetting('proxyPassword', 'Password', secret: true),
    ]),
  ],
);

const romanizationPage = SettingsPage(
  id: 'romanization',
  title: 'Romanization',
  icon: CupertinoIcons.textformat_abc,
  color: HydeColors.cyan,
  sections: [
    SettingsSection([
      ToggleSetting('lyricsRomanizeJapanese', 'Japanese', defaultValue: true),
      ToggleSetting('lyricsRomanizeKorean', 'Korean', defaultValue: true),
      ToggleSetting('lyricsRomanizeRussian', 'Russian'),
      ToggleSetting('lyricsRomanizeUkrainian', 'Ukrainian'),
      ToggleSetting('lyricsRomanizeSerbian', 'Serbian'),
      ToggleSetting('lyricsRomanizeBulgarian', 'Bulgarian'),
      ToggleSetting('lyricsRomanizeBelarusian', 'Belarusian'),
      ToggleSetting('lyricsRomanizeKyrgyz', 'Kyrgyz'),
      ToggleSetting('lyricsRomanizeMacedonian', 'Macedonian'),
    ]),
    SettingsSection([ToggleSetting('lyricsRomanizeCyrillicByLine', 'Detect Cyrillic language per line')]),
  ],
);

const translationPage = SettingsPage(
  id: 'translation',
  title: 'Translation & AI',
  icon: CupertinoIcons.sparkles,
  color: HydeColors.violet,
  sections: [
    SettingsSection([
      ToggleSetting('translateLyrics', 'Translate lyrics'),
      ToggleSetting('autoTranslateLyrics', 'Auto-translate all songs'),
      ToggleSetting('autoTranslateLyricsMismatch', 'Only when language differs'),
      ChoiceSetting('translateMode', 'Mode', [
        ('Literal', 'Original + translation'),
        ('Transcribed', 'Transcribed'),
      ], defaultValue: 'Literal'),
      TextSetting('translateLanguage', 'Target language', placeholder: 'English'),
    ]),
    SettingsSection(header: 'AI provider', [
      ChoiceSetting('aiProvider', 'Provider', [
        ('Google Translate', 'Google Translate (on-device)'),
        ('OpenRouter', 'OpenRouter'),
        ('ChatGPT', 'ChatGPT'),
        ('Perplexity', 'Perplexity'),
        ('Claude', 'Claude'),
        ('Gemini', 'Gemini'),
        ('Grok', 'Grok'),
        ('Custom', 'Custom'),
      ], defaultValue: 'OpenRouter'),
      TextSetting('openRouterApiKey', 'API key', secret: true),
      TextSetting('openRouterBaseUrl', 'Base URL', placeholder: 'https://openrouter.ai/api/v1'),
      TextSetting('openRouterModel', 'Model'),
    ]),
    SettingsSection(header: 'DeepL', [
      TextSetting('deeplApiKey', 'API key', secret: true),
      ChoiceSetting('deeplFormality', 'Formality', [
        ('default', 'Default'),
        ('more', 'More formal'),
        ('less', 'Less formal'),
      ], defaultValue: 'default'),
    ]),
  ],
);

const lyricsPage = SettingsPage(
  id: 'lyrics',
  title: 'Lyrics',
  icon: CupertinoIcons.quote_bubble,
  color: HydeColors.cyan,
  sections: [
    SettingsSection(header: 'Providers', [
      ChoiceSetting('lyricsProvider', 'Preferred provider', _lyricsProviders, defaultValue: 'LRCLIB'),
      // Comma-separated provider order; becomes a drag-to-reorder list in Phase 2.
      TextSetting(
        'lyricsProviderOrder',
        'Fallback order',
        placeholder: 'LRCLIB,SIMPMUSIC,KUGOU,BETTERLYRICS,LYRICSPLUS',
      ),
      ToggleSetting('enableLrclib', 'LRCLIB', defaultValue: true),
      ToggleSetting('enableKugou', 'KuGou', defaultValue: true),
      ToggleSetting('enableSimpMusic', 'SimpMusic', defaultValue: true),
      ToggleSetting('enableBetterLyrics', 'BetterLyrics (word-synced)', defaultValue: true),
      ToggleSetting('enableLyricsPlus', 'LyricsPlus', defaultValue: true),
    ]),
    SettingsSection(header: 'Display', [
      ChoiceSetting('lyricsTextPosition', 'Alignment', [
        ('LEFT', 'Left'),
        ('CENTER', 'Centre'),
        ('RIGHT', 'Right'),
      ], defaultValue: 'LEFT'),
      SliderSetting('lyricsTextSize', 'Text size', min: 20, max: 44, defaultValue: 32, unit: 'pt'),
      SliderSetting('lyricsLineSpacing', 'Line spacing', min: 1, max: 1.8, defaultValue: 1.15),
      ChoiceSetting('lyricsAnimationStyle', 'Animation', [
        ('APPLE', 'Apple Music'),
        ('APPLE_V2', 'Apple Music v2'),
        ('KARAOKE', 'Karaoke'),
        ('GLOW', 'Glow'),
        ('FADE', 'Fade'),
        ('SLIDE', 'Slide'),
        ('VIVIMUSIC_1', 'ViviMusic'),
        ('LYRICS_V2', 'Lyrics v2'),
        ('NONE', 'None'),
      ], defaultValue: 'APPLE'),
      ToggleSetting('appleMusicLyricsBlur', 'Blur inactive lines', defaultValue: true),
      ToggleSetting('lyricsGlowEffect', 'Glow on active line'),
      ToggleSetting('lyricsClick', 'Tap a line to seek', defaultValue: true),
      ToggleSetting('lyricsScrollKey', 'Auto-scroll', defaultValue: true),
    ]),
    SettingsSection([PageLink(romanizationPage), PageLink(translationPage)]),
  ],
);

const audioEnhancerPage = SettingsPage(
  id: 'audioEnhancer',
  title: 'Audio Enhancer',
  icon: CupertinoIcons.slider_horizontal_3,
  color: HydeColors.indigo,
  sections: [
    SettingsSection(header: 'Studio enhancer', [
      ToggleSetting('studioEnhancerEnabled', 'Studio enhancer'),
      ChoiceSetting('enhancerIntensity', 'Intensity', [
        ('SUBTLE', 'Subtle'),
        ('MODERATE', 'Moderate'),
        ('AGGRESSIVE', 'Aggressive'),
      ], defaultValue: 'MODERATE'),
    ]),
    SettingsSection(header: 'Equalizer', [
      ChoiceSetting('equalizerPreset', 'Preset', [
        ('FLAT', 'Flat'),
        ('WARM', 'Warm'),
        ('BRIGHT', 'Bright'),
        ('BASS_BOOST', 'Bass boost'),
        ('VOCAL_ENHANCER', 'Vocal enhancer'),
        ('STUDIO_REFERENCE', 'Studio reference'),
        ('PODCAST', 'Podcast'),
        ('DANCE', 'Dance'),
        ('ACOUSTIC', 'Acoustic'),
      ], defaultValue: 'FLAT'),
      ToggleSetting('equalizerCustomMode', 'Custom bands'),
      ActionSetting('audio.systemEqualizer', 'System equalizer'),
    ]),
    SettingsSection(header: 'Effects', [
      ToggleSetting('virtualizerEnabled', 'Virtualizer'),
      ToggleSetting('reverbEnabled', 'Reverb'),
      ToggleSetting('dynamicsCompressorEnabled', 'Dynamics compressor'),
      SliderSetting('stereoWidth', 'Stereo width', min: 0, max: 2, defaultValue: 1),
      SliderSetting('presenceBoost', 'Presence boost', min: 0, max: 1, defaultValue: 0),
    ]),
  ],
);

const playbackPage = SettingsPage(
  id: 'playback',
  title: 'Playback',
  icon: CupertinoIcons.play_circle,
  color: HydeColors.indigo,
  sections: [
    SettingsSection(header: 'Quality', [
      ChoiceSetting('audioQuality', 'Streaming quality', _audioQuality, defaultValue: 'AUTO'),
      ToggleSetting('audioNormalization', 'Normalize volume', defaultValue: true),
      ToggleSetting('skipSilence', 'Skip silence'),
      ToggleSetting('enableOffload', 'Audio offload', subtitle: 'Lower battery use; disables effects'),
      PageLink(audioEnhancerPage),
    ]),
    SettingsSection(header: 'Transitions', [
      ToggleSetting('crossfadeEnabled', 'Crossfade'),
      SliderSetting('crossfadeDurationFloat', 'Crossfade duration', min: 1, max: 12, defaultValue: 5, unit: 's'),
      ToggleSetting('crossfadeGapless', 'Keep gapless albums gapless', defaultValue: true),
    ]),
    SettingsSection(header: 'Queue', [
      ToggleSetting('persistentQueue', 'Restore queue on launch', defaultValue: true),
      ToggleSetting('rememberShuffleAndRepeat', 'Remember shuffle & repeat', defaultValue: true),
      ToggleSetting('persistentShuffleAcrossQueues', 'Keep shuffle across queues'),
      ToggleSetting('smartShuffleEnabled', 'AI Shuffle', subtitle: 'Shuffle flows by artist, album and length, never stuck on one artist'),
      ToggleSetting('similarContent', 'Autoplay similar songs', defaultValue: true),
      ToggleSetting('autoLoadMore', 'Load more automatically', defaultValue: true),
      ToggleSetting('disableLoadMoreWhenRepeatAll', 'Don’t load more on Repeat All'),
      ToggleSetting('preventDuplicateTracksInQueue', 'Prevent duplicates in queue'),
      ToggleSetting('autoSkipNextOnError', 'Skip to next on error'),
    ]),
    SettingsSection(header: 'Behaviour', [
      ToggleSetting('seekExtraSeconds', 'Repeated taps add seek time'),
      ToggleSetting('pauseOnMute', 'Pause when muted'),
      ToggleSetting('resumeOnBluetoothConnect', 'Resume on Bluetooth connect'),
      ToggleSetting('keepScreenOn', 'Keep screen on in player'),
      ToggleSetting('stopMusicOnTaskClear', 'Stop when app is swiped away'),
      ToggleSetting('forceStopOnTaskClear', 'Force stop when swiped away'),
      ToggleSetting('pipEnabled', 'Picture-in-picture for videos'),
      ToggleSetting('ttsAnnouncementEnabled', 'Announce songs (TTS)'),
      ToggleSetting('musicHapticsEnabled', 'Music haptics'),
      SliderSetting(
        'sleepTimerDefault',
        'Default sleep timer',
        min: 5,
        max: 120,
        defaultValue: 30,
        divisions: 23,
        unit: 'min',
      ),
    ]),
    SettingsSection(header: 'Casting & SponsorBlock', [
      ToggleSetting('enableGoogleCast', 'Google Cast', defaultValue: true),
      ToggleSetting('sponsorBlockEnabled', 'SponsorBlock', subtitle: 'Skip non-music segments in music videos'),
      TextSetting('sponsorBlockCategories', 'SponsorBlock categories', placeholder: 'music_offtopic,intro,outro'),
    ]),
  ],
);

const downloadPage = SettingsPage(
  id: 'download',
  title: 'Download',
  icon: CupertinoIcons.arrow_down_circle,
  color: HydeColors.green,
  sections: [
    SettingsSection([
      ToggleSetting('autoDownloadOnLike', 'Download songs when liked'),
      ActionSetting('download.manage', 'Manage downloads'),
      ActionSetting(
        'download.clearAll',
        'Remove all downloads',
        destructive: true,
        confirm: 'Remove every downloaded song?',
      ),
    ]),
  ],
);

const filesPage = SettingsPage(
  id: 'files',
  title: 'Files & Folders',
  icon: CupertinoIcons.folder,
  color: HydeColors.orange,
  sections: [
    SettingsSection(header: 'Local scan', [
      TextSetting('scanPaths', 'Folders to scan', placeholder: '/Music'),
      TextSetting('excludedScanPaths', 'Excluded folders'),
      ActionSetting('local.grantPermission', 'Grant audio permission'),
    ]),
  ],
);

const appPage = SettingsPage(
  id: 'app',
  title: 'App',
  icon: CupertinoIcons.slider_horizontal_3,
  color: HydeColors.slate,
  sections: [
    SettingsSection([
      TextSetting('appLanguage', 'App language', placeholder: 'System default'),
      ActionSetting('app.defaultLinks', 'Open music links in Hyde', subtitle: 'Android “Open by default”'),
    ]),
    SettingsSection(header: 'Updates', [
      ToggleSetting('checkForUpdates', 'Check for updates', defaultValue: true),
      ToggleSetting('updateNotifications', 'Update notifications', defaultValue: true),
      ActionSetting('app.checkNow', 'Software Update', subtitle: 'Check, download and install new versions'),
    ]),
    SettingsSection(header: 'Privacy', [
      ToggleSetting('pauseListenHistory', 'Pause listen history'),
      ToggleSetting('pauseSearchHistory', 'Pause search history'),
      SliderSetting('historyDuration', 'Count as listened after', min: 1, max: 60, defaultValue: 30, unit: 's'),
      ToggleSetting('disableScreenshot', 'Block screenshots'),
      ToggleSetting('anonymousAnalytics', 'Anonymous analytics'),
      ActionSetting(
        'privacy.clearListenHistory',
        'Clear listen history',
        destructive: true,
        confirm: 'Clear all listen history?',
      ),
      ActionSetting(
        'privacy.clearSearchHistory',
        'Clear search history',
        destructive: true,
        confirm: 'Clear all search history?',
      ),
    ]),
    SettingsSection(header: 'Developer', [ToggleSetting('developerMode', 'Developer mode')]),
  ],
);

const storagePage = SettingsPage(
  id: 'storage',
  title: 'Storage & Cache',
  icon: CupertinoIcons.archivebox,
  color: HydeColors.indigo,
  sections: [
    SettingsSection(header: 'Usage', [
      InfoSetting('storage.song', 'Song cache'),
      InfoSetting('storage.download', 'Downloads'),
      InfoSetting('storage.image', 'Image cache'),
    ]),
    SettingsSection(header: 'Song cache', [
      SliderSetting('maxSongCacheSize', 'Max size', min: 128, max: 8192, defaultValue: 1024, unit: 'MB', isInt: true),
      ActionSetting('storage.clearSongCache', 'Clear song cache', destructive: true, confirm: 'Clear cached songs?'),
    ]),
    SettingsSection(header: 'Image cache', [
      SliderSetting('maxImageCacheSize', 'Max size', min: 128, max: 2048, defaultValue: 512, unit: 'MB', isInt: true),
      ActionSetting('storage.clearImageCache', 'Clear image cache', destructive: true),
    ]),
  ],
);

const backupPage = SettingsPage(
  id: 'backup',
  title: 'Backup & Restore',
  icon: CupertinoIcons.clock,
  color: HydeColors.mint,
  sections: [
    SettingsSection(footer: 'Backups are compatible with the previous Hyde Music app.', [
      ActionSetting('backup.create', 'Back up'),
      ActionSetting('backup.restore', 'Restore', confirm: 'Restoring replaces your current library and settings.'),
    ]),
    SettingsSection(header: 'Import', [
      ActionSetting('import.spotify', 'Import from Spotify'),
      ActionSetting('import.csv', 'Import playlist from CSV'),
      ActionSetting('import.online', 'Import online playlist'),
    ]),
  ],
);

const logsPage = SettingsPage(
  id: 'logs',
  title: 'Logs',
  icon: CupertinoIcons.doc_text,
  color: HydeColors.tan,
  sections: [
    SettingsSection([
      ActionSetting('logs.crash', 'Crash reports'),
      ActionSetting('logs.listenTogether', 'Listen Together logs'),
      ActionSetting('logs.share', 'Share logs'),
    ]),
  ],
);

const supportPage = SettingsPage(
  id: 'support',
  title: 'Support Development',
  icon: CupertinoIcons.heart,
  color: HydeColors.pink,
  sections: [
    SettingsSection([
      ActionSetting('support.patreon', 'Patreon', subtitle: 'Monthly support'),
      ActionSetting('support.upi', 'UPI payment', subtitle: 'Direct payment (India only)'),
      ActionSetting('support.crypto', 'Cryptocurrency', subtitle: 'Bitcoin, Ethereum, Solana'),
    ]),
  ],
);

const aboutPage = SettingsPage(
  id: 'about',
  title: 'About',
  icon: CupertinoIcons.info_circle,
  color: HydeColors.label,
  sections: [
    SettingsSection([
      ActionSetting('about.website', 'Website'),
      ActionSetting('about.github', 'GitHub'),
      ActionSetting('about.telegram', 'Telegram'),
      ActionSetting('about.discord', 'Discord community'),
      ActionSetting('about.privacy', 'Privacy policy'),
      ActionSetting('about.contact', 'Contact'),
      ActionSetting('about.licenses', 'Open-source licences'),
    ]),
  ],
);

/// Root list, grouped like the reference screenshot.
const settingsGroups = <List<SettingsPage>>[
  [integrationsPage, appearancePage],
  [localLibraryPage, contentPage, lyricsPage, playbackPage],
  [downloadPage, filesPage],
  [appPage, storagePage, backupPage, logsPage],
  [supportPage, aboutPage],
];

/// Flattened (page, item) pairs for "Search settings".
Iterable<(SettingsPage, SettingItem)> allSettings() sync* {
  final seen = <String>{};
  Iterable<(SettingsPage, SettingItem)> walk(SettingsPage p) sync* {
    if (!seen.add(p.id)) return;
    for (final s in p.sections) {
      for (final i in s.items) {
        if (i is PageLink) {
          yield* walk(i.page);
        } else {
          yield (p, i);
        }
      }
    }
  }

  for (final g in settingsGroups) {
    for (final p in g) {
      yield* walk(p);
    }
  }
}


/// Settings the Flutter app actually honours. The catalog above still lists
/// every native preference (so values survive the update and a backup made
/// here restores there), but rows for features that don't exist in this app
/// are not shown — a switch that does nothing is worse than no switch.
/// docs/07_SETTINGS_MAP.md lists what is hidden and why.
const supportedSettingKeys = <String>{
  // Account & integrations
  'ytmSync', 'useLoginForBrowse',
  'discordRPCEnable', 'discordUseDetails', 'discordStatus', 'discordActivityType', 'discordActivityName',
  'discordButton1Visible', 'discordButton1Text', 'discordButton2Visible', 'discordButton2Text',
  'lastfmScrobblingEnable', 'lastfmUseNowPlaying', 'lastfmUseSendLikes', 'scrobbleDelaySeconds',
  'listenTogetherUsername', 'listenTogetherServerUrl', 'listenTogetherAutoApproval',
  // Appearance & behaviour
  // (Desktop: no dynamic icon, launch tab, swipe gestures or screen-on lock.)
  'darkMode', 'glassQuality', 'randomizeHomeOrder', 'smartShuffleEnabled',
  'show_liked_playlist', 'show_downloaded_playlist', 'show_top_playlist',
  // Content
  'contentLanguage', 'contentCountry', 'hideExplicit', 'hideVideoSongs', 'discover', 'topSize',
  // Lyrics
  'enableLrclib', 'lyricsTextPosition', 'lyricsTextSize', 'lyricsLineSpacing', 'appleMusicLyricsBlur',
  'lyricsGlowEffect', 'lyricsClick',
  // Playback
  'audioQuality', 'audioNormalization', 'skipSilence', 'persistentQueue', 'rememberShuffleAndRepeat',
  'persistentShuffleAcrossQueues', 'similarContent', 'autoLoadMore', 'disableLoadMoreWhenRepeatAll',
  'preventDuplicateTracksInQueue', 'autoSkipNextOnError',
  'sponsorBlockEnabled', 'sponsorBlockCategories',
  // Downloads, files, app
  'autoDownloadOnLike', 'excludedScanPaths', 'checkForUpdates', 'pauseListenHistory', 'pauseSearchHistory',
  'historyDuration',
};

/// Actions / info rows whose feature isn't in this app.
const _unsupportedActions = <String>{
  'storage.clearSongCache', 'storage.song', 'account.tokenLogin', 'logs.crash',
  // Android-only system screens and services, not on Windows / Linux.
  'audio.systemEqualizer', 'app.defaultLinks', 'nearbySync.open', 'local.grantPermission', 'local.scan',
};

bool isSettingAvailable(SettingItem item) => switch (item) {
  ToggleSetting(:final key) => supportedSettingKeys.contains(key),
  ChoiceSetting(:final key) => supportedSettingKeys.contains(key),
  SliderSetting(:final key) => supportedSettingKeys.contains(key),
  TextSetting(:final key) => supportedSettingKeys.contains(key),
  ActionSetting(:final action) => !_unsupportedActions.contains(action),
  InfoSetting(:final info) => !_unsupportedActions.contains(info),
  PageLink(:final page) => isPageAvailable(page),
};

/// Pages rendered by their own screen are always shown.
const _customPages = {'account', 'about', 'support', 'logs', 'hydesync'};

/// The sections of [page] with only the rows that work; empty sections dropped.
List<SettingsSection> visibleSections(SettingsPage page) => [
  for (final section in page.sections)
    if (section.items.where(isSettingAvailable).toList() case final items when items.isNotEmpty)
      SettingsSection(items, header: section.header, footer: section.footer),
];

bool isPageAvailable(SettingsPage page) => _customPages.contains(page.id) || visibleSections(page).isNotEmpty;
