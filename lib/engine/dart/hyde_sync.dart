import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';

import '../models.dart';
import 'database.dart';
import 'settings_store.dart';
import 'youtube.dart';

/// Hyde Sync (port of supabase/*): an email account that backs up likes,
/// library songs, playlists, saved albums and followed artists to the cloud
/// and merges them on another phone. Talks to the same Supabase project as
/// the native app (auth: GoTrue, data: PostgREST), so accounts carry over.
class HydeSync {
  HydeSync({required this.db, required this.settings, required this.youtube, required this.emit, required this.onLibraryChanged, http.Client? client})
    : _http = client ?? http.Client();

  final HydeDatabase db;
  final SettingsStore settings;
  final YouTube youtube;
  final void Function(Map<String, Object?> state) emit;
  final void Function() onLibraryChanged;
  final http.Client _http;

  // Public project URL and publishable (anon) key — the same values the
  // native build shipped; row access is enforced server-side per user.
  static const _url = 'https://yblgvozpaxuruqxrpylc.supabase.co';
  static const _key = 'sb_publishable_lx2oJJgkSv1W8rFJoQ_lRw_xMZl4TaN';

  String _state = 'idle';
  String? _message;

  String? get _access => settings.string('hydeSyncAccessToken');
  String? get _refresh => settings.string('hydeSyncRefreshToken');
  String? get _userId => settings.string('hydeSyncUserId');
  bool get signedIn => _refresh != null && _userId != null;

  void _set(String state, [String? message]) {
    _state = state;
    _message = message;
    publish();
  }

  void publish() => emit({
    'topic': 'hydesync',
    'signedIn': signedIn,
    'email': settings.string('hydeSyncEmail'),
    'state': _state,
    'message': _message,
    'lastSync': settings['hydeSyncLastSync'],
  });

  // ── Auth ─────────────────────────────────────────────────────────────────

  static String _authError(Map body, int status) {
    final msg = (body['msg'] ?? body['error_description'] ?? body['message'] ?? body['error'])?.toString() ?? '';
    if (msg.contains('Invalid login')) return 'Wrong email or password';
    if (msg.contains('already registered')) return 'That email already has an account — sign in instead';
    if (msg.contains('Email not confirmed')) return 'Confirm your email first (check your inbox), then sign in';
    if (msg.toLowerCase().contains('password')) return msg;
    return msg.isEmpty ? 'Hyde Sync answered $status' : msg;
  }

  Future<Map<String, Object?>> _auth(String path, Map<String, Object?> body) async {
    final res = await _http
        .post(
          Uri.parse('$_url/auth/v1/$path'),
          headers: {'apikey': _key, 'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 20));
    final json = (res.body.isEmpty ? const {} : jsonDecode(utf8.decode(res.bodyBytes))) as Map;
    if (res.statusCode >= 400) throw FormatException(_authError(json, res.statusCode));
    return json.cast<String, Object?>();
  }

  Future<void> _storeSession(Map<String, Object?> session) async {
    await settings.write('hydeSyncAccessToken', session['access_token']);
    await settings.write('hydeSyncRefreshToken', session['refresh_token']);
    final expiresIn = (session['expires_in'] as num?)?.toInt() ?? 3600;
    await settings.write('hydeSyncExpiresAt', DateTime.now().millisecondsSinceEpoch + expiresIn * 1000);
  }

  Future<String> _token() async {
    final expires = settings['hydeSyncExpiresAt'] as int? ?? 0;
    if (_access != null && DateTime.now().millisecondsSinceEpoch < expires - 60000) return _access!;
    final refresh = _refresh;
    if (refresh == null) throw const FormatException('Sign in to Hyde Sync first');
    try {
      await _storeSession(await _auth('token?grant_type=refresh_token', {'refresh_token': refresh}));
    } on FormatException {
      await _clearSession();
      publish();
      throw const FormatException('Your Hyde Sync session expired — sign in again');
    }
    return _access!;
  }

  Future<void> _clearSession() async {
    for (final k in const ['hydeSyncAccessToken', 'hydeSyncRefreshToken', 'hydeSyncExpiresAt', 'hydeSyncUserId', 'hydeSyncEmail']) {
      await settings.write(k, null);
    }
  }

  Future<void> signIn(String email, String password, {bool create = false}) async {
    if (email.isEmpty || password.isEmpty) throw const FormatException('Enter your email and password');
    _set('loading');
    try {
      final Map<String, Object?> session;
      if (create) {
        final res = await _auth('signup', {'email': email, 'password': password});
        // With email confirmation on, sign-up returns the user but no session.
        if (res['access_token'] == null) {
          _set('idle');
          throw const FormatException('Account created — confirm the email we sent you, then sign in');
        }
        session = res;
      } else {
        session = await _auth('token?grant_type=password', {'email': email, 'password': password});
      }
      await _storeSession(session);
      final authId = (session['user'] as Map?)?['id'] as String?;
      if (authId == null) throw const FormatException('Sign-in didn’t return an account');
      final (userId, isNew) = await _ensureUserRow(authId, email);
      await settings.write('hydeSyncUserId', userId);
      await settings.write('hydeSyncEmail', email);
      publish();
      // A new account starts from this phone's library; an existing one merges.
      await sync(pull: !isNew);
    } catch (e) {
      if (_state != 'idle') _set('error', e is FormatException ? e.message : 'Couldn’t reach Hyde Sync');
      rethrow;
    }
  }

  Future<void> signOut() async {
    final token = _access;
    if (token != null) {
      unawaited(
        _http
            .post(Uri.parse('$_url/auth/v1/logout'), headers: {'apikey': _key, 'Authorization': 'Bearer $token'})
            .then<void>((_) {})
            .catchError((_) {}),
      );
    }
    await _clearSession();
    _set('idle');
  }

  // ── PostgREST ────────────────────────────────────────────────────────────

  Future<List<Map<String, Object?>>> _select(String table, String query) async {
    final out = <Map<String, Object?>>[];
    // PostgREST pages at 1000 rows.
    for (var offset = 0; ; offset += 1000) {
      final res = await _http
          .get(
            Uri.parse('$_url/rest/v1/$table?$query&limit=1000&offset=$offset'),
            headers: {'apikey': _key, 'Authorization': 'Bearer ${await _token()}'},
          )
          .timeout(const Duration(seconds: 30));
      if (res.statusCode >= 400) throw FormatException('Hyde Sync couldn’t read $table (${res.statusCode})');
      final rows = (jsonDecode(utf8.decode(res.bodyBytes)) as List).cast<Map>();
      out.addAll(rows.map((r) => r.cast<String, Object?>()));
      if (rows.length < 1000) return out;
    }
  }

  Future<void> _upsert(String table, List<Map<String, Object?>> rows, {String? onConflict}) async {
    for (var i = 0; i < rows.length; i += 500) {
      final chunk = rows.sublist(i, i + 500 > rows.length ? rows.length : i + 500);
      final res = await _http
          .post(
            Uri.parse('$_url/rest/v1/$table${onConflict == null ? '' : '?on_conflict=$onConflict'}'),
            headers: {
              'apikey': _key,
              'Authorization': 'Bearer ${await _token()}',
              'Content-Type': 'application/json',
              'Prefer': 'resolution=merge-duplicates,return=minimal',
            },
            body: jsonEncode(chunk),
          )
          .timeout(const Duration(seconds: 30));
      if (res.statusCode >= 400) throw FormatException('Hyde Sync couldn’t save $table (${res.statusCode})');
    }
  }

  Future<void> _delete(String table, String query) async {
    final res = await _http
        .delete(Uri.parse('$_url/rest/v1/$table?$query'), headers: {'apikey': _key, 'Authorization': 'Bearer ${await _token()}'})
        .timeout(const Duration(seconds: 30));
    if (res.statusCode >= 400) throw FormatException('Hyde Sync couldn’t update $table (${res.statusCode})');
  }

  Future<(String userId, bool isNew)> _ensureUserRow(String authId, String email) async {
    Future<String?> find() async =>
        (await _select('users', 'select=id&auth_id=eq.$authId')).firstOrNull?['id'] as String?;
    final existing = await find();
    if (existing != null) return (existing, false);
    await _upsert('users', [
      {'auth_id': authId, 'email': email, 'is_active': true},
    ], onConflict: 'auth_id');
    final created = await find();
    if (created == null) throw const FormatException('Hyde Sync couldn’t create your profile');
    return (created, true);
  }

  // ── Sync ─────────────────────────────────────────────────────────────────

  static String? _iso(Object? epochMs) =>
      epochMs is int ? DateTime.fromMillisecondsSinceEpoch(epochMs, isUtc: true).toIso8601String() : null;

  static int? _epoch(Object? iso) => iso is String ? DateTime.tryParse(iso)?.millisecondsSinceEpoch : null;

  /// Merges the cloud copy into this phone ([pull]), then uploads this
  /// phone's library. Nothing is ever deleted locally by a sync.
  Future<void> sync({bool pull = true}) async {
    final userId = _userId;
    if (userId == null) throw const FormatException('Sign in to Hyde Sync first');
    if (_state == 'syncing') return;
    try {
      if (pull) {
        _set('syncing', 'Downloading your library…');
        await _pull(userId);
        onLibraryChanged();
      }
      _set('syncing', 'Uploading your library…');
      await _push(userId);
      await settings.write('hydeSyncLastSync', DateTime.now().millisecondsSinceEpoch);
      _set('success', 'Everything is up to date');
    } catch (e) {
      _set('error', e is FormatException ? e.message : 'Sync failed — check your connection');
      rethrow;
    }
  }

  Future<void> _pull(String userId) async {
    final songs = await _select('songs', 'select=*&user_id=eq.$userId');
    final wanted = [
      for (final s in songs)
        if (s['is_local'] != true && (s['liked'] == true || s['in_library'] == true)) s,
    ];
    // Cloud rows have no artist names; fetch real metadata for songs we don't know yet.
    final known = await db.flags(wanted.map((s) => s['id'] as String));
    final missing = [for (final s in wanted) if (!known.containsKey(s['id'])) s['id'] as String];
    final fetched = <String, Track>{};
    if (missing.isNotEmpty) {
      try {
        for (final t in await youtube.queue(missing)) {
          fetched[t.id] = t;
        }
      } catch (_) {}
    }
    for (final s in wanted) {
      final id = s['id'] as String;
      final track = fetched[id] ??
          Track(
            id: id,
            title: s['title'] as String? ?? '',
            artists: const [],
            thumbnailUrl: s['thumbnail_url'] as String?,
            duration: Duration(seconds: (s['duration_seconds'] as num?)?.toInt() ?? 0),
          );
      await db.ensureTrack(track);
      final flags = known[id];
      await db.db.update(
        'song',
        {
          if (s['liked'] == true && !(flags?.liked ?? false)) ...{
            'liked': 1,
            'likedDate': _epoch(s['liked_at']) ?? HydeDatabase.now(),
          },
          if ((s['in_library'] == true || s['liked'] == true) && !(flags?.inLibrary ?? false))
            'inLibrary': _epoch(s['library_added_at']) ?? _epoch(s['liked_at']) ?? HydeDatabase.now(),
        }..removeWhere((_, v) => v == null),
        where: 'id = ?',
        whereArgs: [id],
      ).catchError((_) => 0);
    }

    // Playlists: create missing ones (same id), fill the ones that are empty here.
    final playlists = await _select('playlists', 'select=*&user_id=eq.$userId');
    final links = await _select('playlist_songs', 'select=*&user_id=eq.$userId&order=position.asc');
    final songById = {for (final s in songs) s['id'] as String: s};
    for (final p in playlists) {
      final id = p['id'] as String;
      final exists = (await db.db.query('playlist', columns: ['id'], where: 'id = ?', whereArgs: [id])).isNotEmpty;
      if (!exists) {
        await db.db.insert('playlist', {
          'id': id,
          'name': p['name'] as String? ?? 'Playlist',
          'createdAt': HydeDatabase.now(),
          'lastUpdateTime': HydeDatabase.now(),
          'isEditable': p['is_editable'] == false ? 0 : 1,
          'bookmarkedAt': HydeDatabase.now(),
          'thumbnailUrl': p['thumbnail_url'],
          'isLocal': 0,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      if ((await db.playlistSongs(id)).isNotEmpty) continue;
      final ids = [for (final l in links) if (l['playlist_id'] == id) l['song_id'] as String];
      if (ids.isEmpty) continue;
      final unknown = [for (final sid in ids) if (!fetched.containsKey(sid) && await db.track(sid) == null) sid];
      if (unknown.isNotEmpty) {
        try {
          for (final t in await youtube.queue(unknown)) {
            fetched[t.id] = t;
          }
        } catch (_) {}
      }
      final tracks = <Track>[];
      for (final sid in ids) {
        final t = fetched[sid] ?? await db.track(sid);
        if (t != null) {
          tracks.add(t);
        } else if (songById[sid] case final row?) {
          tracks.add(Track(id: sid, title: row['title'] as String? ?? '', artists: const [], thumbnailUrl: row['thumbnail_url'] as String?));
        }
      }
      await db.setPlaylistSongs(id, tracks);
    }

    for (final a in await _select('artists', 'select=*&user_id=eq.$userId&bookmarked=eq.true')) {
      if (a['is_local'] == true) continue;
      await db.setArtistBookmarked(
        Artist(
          id: a['id'] as String,
          name: a['name'] as String? ?? '',
          thumbnailUrl: a['thumbnail_url'] as String?,
          channelId: a['youtube_channel_id'] as String?,
        ),
        true,
      );
    }
    for (final a in await _select('albums', 'select=*&user_id=eq.$userId&bookmarked=eq.true')) {
      if (a['is_local'] == true || await db.isAlbumBookmarked(a['id'] as String)) continue;
      await db.saveAlbum(
        Album(
          id: a['id'] as String,
          title: a['title'] as String? ?? '',
          artists: const [],
          year: (a['release_year'] as num?)?.toInt(),
          thumbnailUrl: a['thumbnail_url'] as String?,
        ),
        const [],
        bookmarked: true,
      );
    }
  }

  Future<void> _push(String userId) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final songs = await db.db.rawQuery(
      'SELECT s.*, (SELECT COALESCE(SUM(count), 0) FROM playCount WHERE song = s.id) AS plays FROM song s '
      'WHERE s.isLocal = 0 AND (s.liked = 1 OR s.inLibrary IS NOT NULL OR s.id IN (SELECT songId FROM playlist_song_map))',
    );
    await _upsert('songs', [
      for (final s in songs)
        {
          'id': s['id'],
          'user_id': userId,
          'title': s['title'],
          'duration_seconds': ((s['duration'] as int?) ?? 0) < 0 ? null : s['duration'],
          'thumbnail_url': s['thumbnailUrl'],
          'liked': s['liked'] == 1,
          'liked_at': _iso(s['likedDate']),
          'in_library': s['inLibrary'] != null,
          'library_added_at': _iso(s['inLibrary']),
          'is_downloaded': s['isDownloaded'] == 1,
          'is_local': false,
          'play_count': s['plays'],
          'total_play_time_ms': s['totalPlayTime'],
          'synced_at': now,
          'updated_at': now,
        },
    ], onConflict: 'id,user_id');

    final playlists = await db.db.rawQuery(
      'SELECT p.*, (SELECT COUNT(*) FROM playlist_song_map WHERE playlistId = p.id) AS songCount FROM playlist p',
    );
    await _upsert('playlists', [
      for (final p in playlists)
        {
          'id': p['id'],
          'user_id': userId,
          'name': p['name'],
          'thumbnail_url': p['thumbnailUrl'],
          'is_editable': p['isEditable'] != 0,
          'is_local': false,
          'total_songs': p['songCount'],
          'updated_at': now,
        },
    ], onConflict: 'id,user_id');

    // Playlist contents are replaced wholesale, like the native app.
    final maps = await db.db.rawQuery(
      'SELECT m.* FROM playlist_song_map m JOIN song s ON s.id = m.songId WHERE s.isLocal = 0 ORDER BY m.playlistId, m.position',
    );
    await _delete('playlist_songs', 'user_id=eq.$userId');
    await _upsert('playlist_songs', [
      for (final m in maps)
        {
          'user_id': userId,
          'playlist_id': m['playlistId'],
          'song_id': m['songId'],
          'position': m['position'],
          'youtube_set_video_id': m['setVideoId'],
        },
    ]);

    final artists = await db.db.query('artist', where: 'bookmarkedAt IS NOT NULL AND isLocal = 0');
    await _upsert('artists', [
      for (final a in artists)
        {
          'id': a['id'],
          'user_id': userId,
          'name': a['name'],
          'thumbnail_url': a['thumbnailUrl'],
          'youtube_channel_id': a['channelId'],
          'is_local': false,
          'bookmarked': true,
          'bookmarked_at': _iso(a['bookmarkedAt']),
          'updated_at': now,
        },
    ], onConflict: 'id,user_id');

    final albums = await db.db.query('album', where: 'bookmarkedAt IS NOT NULL AND isLocal = 0');
    await _upsert('albums', [
      for (final a in albums)
        {
          'id': a['id'],
          'user_id': userId,
          'title': a['title'],
          'release_year': a['year'],
          'thumbnail_url': a['thumbnailUrl'],
          'total_songs': a['songCount'],
          'total_duration_seconds': a['duration'],
          'bookmarked': true,
          'bookmarked_at': _iso(a['bookmarkedAt']),
          'is_local': false,
          'updated_at': now,
        },
    ], onConflict: 'id,user_id');

    final res = await _http.patch(
      Uri.parse('$_url/rest/v1/users?id=eq.$userId'),
      headers: {'apikey': _key, 'Authorization': 'Bearer ${await _token()}', 'Content-Type': 'application/json'},
      body: jsonEncode({'last_sync_at': now}),
    );
    if (res.statusCode >= 400) throw FormatException('Hyde Sync couldn’t finish (${res.statusCode})');
  }

  void close() => _http.close();
}
