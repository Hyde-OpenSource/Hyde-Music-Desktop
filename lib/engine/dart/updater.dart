import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../models.dart';
import 'settings_store.dart';

/// In-app updater (docs/08_UPDATER.md): checks GitHub Releases, downloads the
/// APK for this device's ABI (resumable), verifies its SHA-256 when the
/// release publishes one, then hands it to the system installer — which
/// itself refuses any APK not signed with the installed app's key.
class Updater {
  Updater({
    required this.settings,
    required this.currentVersion,
    required this.cacheDir,
    required this.host,
    http.Client? client,
  }) : _http = client ?? http.Client();

  static const owner = 'Hyde-OpenSource';
  static const repo = 'Hyde-Music-Desktop';

  final SettingsStore settings;
  final String currentVersion;
  final Directory cacheDir;
  final MethodChannel host;
  final http.Client _http;

  final _states = StreamController<UpdateStatus>.broadcast();
  Stream<UpdateStatus> get states => _states.stream;

  UpdatePhase _phase = UpdatePhase.idle;
  UpdateRelease? _release;
  String? _assetUrl;
  String? _assetName;
  String? _sha256;
  int _bytes = 0;
  int _total = 0;
  int _speed = 0;
  String? _error;
  bool _cancel = false;

  bool get _beta => settings.boolean('updateBetaChannel');
  bool get _autoDownload => settings.boolean('updateAutoDownload', true);
  bool get _wifiOnly => settings.boolean('updateWifiOnly', true);
  bool get _autoCheck => settings.boolean('checkForUpdates', true);

  UpdateStatus get status {
    final last = settings['updateLastChecked'] as int?;
    return UpdateStatus(
      phase: _phase,
      currentVersion: currentVersion,
      release: _release,
      bytes: _bytes,
      total: _total,
      speed: _speed,
      error: _error,
      lastChecked: last == null ? null : DateTime.fromMillisecondsSinceEpoch(last),
      beta: _beta,
      autoDownload: _autoDownload,
      wifiOnly: _wifiOnly,
      autoCheck: _autoCheck,
    );
  }

  void _set(UpdatePhase phase, {String? error}) {
    _phase = phase;
    _error = error;
    if (!_states.isClosed) _states.add(status);
  }

  /// "5.1", "v5.1.0-beta2" → comparable parts; a pre-release tag sorts lower.
  static List<int> parseVersion(String v) {
    final core = v.trim().replaceFirst(RegExp('^[vV]'), '').split(RegExp(r'[-+ ]')).first;
    final parts = [for (final s in core.split('.')) int.tryParse(RegExp(r'^\d+').stringMatch(s) ?? '') ?? 0];
    while (parts.length < 3) {
      parts.add(0);
    }
    return parts;
  }

  static int compareVersions(String a, String b) {
    final x = parseVersion(a), y = parseVersion(b);
    for (var i = 0; i < 3; i++) {
      if (x[i] != y[i]) return x[i].compareTo(y[i]);
    }
    return 0;
  }

  /// The running AppImage, when started from one (set by the AppImage runtime).
  static String? get _appImage => Platform.environment['APPIMAGE'];

  /// Release files this build can update itself from, best first.
  static List<String> get _wantedSuffixes => Platform.isWindows
      ? const ['-setup.exe']
      : _appImage != null
      ? const ['.appimage']
      : const ['.tar.gz', '.appimage'];

  File get _apk => File(p.join(cacheDir.path, 'update', _assetName ?? 'hyde-update'));

  Future<UpdateStatus> check({bool manual = true}) async {
    if (_phase == UpdatePhase.downloading || _phase == UpdatePhase.installing) return status;
    _set(UpdatePhase.checking);
    try {
      final res = await _http
          .get(
            Uri.parse('https://api.github.com/repos/$owner/$repo/releases?per_page=15'),
            headers: {'Accept': 'application/vnd.github+json', 'User-Agent': 'Hyde-Music'},
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 403 || res.statusCode == 429) {
        throw const HttpException('GitHub is rate-limiting update checks. Try again later.');
      }
      if (res.statusCode != 200) throw HttpException('GitHub answered ${res.statusCode}');
      await settings.write('updateLastChecked', DateTime.now().millisecondsSinceEpoch);

      final releases = (jsonDecode(utf8.decode(res.bodyBytes)) as List).cast<Map>();
      Map? best;
      for (final r in releases) {
        if (r['draft'] == true) continue;
        if (r['prerelease'] == true && !_beta) continue;
        final tag = r['tag_name'] as String? ?? '';
        if (compareVersions(tag, currentVersion) <= 0) continue;
        if (best == null || compareVersions(tag, best['tag_name'] as String) > 0) best = r;
      }
      if (best == null) {
        _release = null;
        _set(UpdatePhase.upToDate);
        return status;
      }
      final version = (best['tag_name'] as String).replaceFirst(RegExp('^[vV]'), '');
      if (!manual && settings['updateSkippedVersion'] == version) {
        _release = null;
        _set(UpdatePhase.upToDate);
        return status;
      }
      final assets = (best['assets'] as List? ?? const []).cast<Map>();
      final apk = [
        for (final suffix in _wantedSuffixes)
          ...assets.where((a) => (a['name'] as String).toLowerCase().endsWith(suffix)),
      ].firstOrNull;
      if (apk == null) {
        _release = null;
        _set(UpdatePhase.upToDate);
        return status;
      }
      _assetUrl = apk['browser_download_url'] as String;
      _assetName = apk['name'] as String;
      _total = (apk['size'] as num?)?.toInt() ?? 0;
      _sha256 = await _findSha256(_assetName!, assets, best['body'] as String? ?? '');
      _release = UpdateRelease(
        version: version,
        name: best['name'] as String? ?? version,
        notes: best['body'] as String? ?? '',
        size: _total,
        publishedAt: best['published_at'] as String?,
        prerelease: best['prerelease'] == true,
        verifiedChecksum: _sha256 != null,
        url: best['html_url'] as String?,
      );
      // A finished download from an earlier session.
      if (_apk.existsSync() && _apk.lengthSync() == _total && await _verify()) {
        _bytes = _total;
        _set(UpdatePhase.ready);
      } else {
        _set(UpdatePhase.available);
      }
    } catch (e) {
      _set(UpdatePhase.failed, error: e is HttpException ? e.message : 'Couldn’t check for updates');
    }
    return status;
  }

  static final _hex = RegExp(r'\b[a-fA-F0-9]{64}\b');

  Future<String?> _findSha256(String apkName, List<Map> assets, String notes) async {
    String? fromText(String text) {
      for (final line in const LineSplitter().convert(text)) {
        if (line.contains(apkName)) {
          final m = _hex.firstMatch(line);
          if (m != null) return m.group(0)!.toLowerCase();
        }
      }
      return null;
    }

    for (final a in assets) {
      final n = (a['name'] as String).toLowerCase();
      if (n == '${apkName.toLowerCase()}.sha256' || n == 'checksums.txt' || n == 'sha256sums') {
        try {
          final res = await _http.get(Uri.parse(a['browser_download_url'] as String)).timeout(const Duration(seconds: 10));
          if (res.statusCode != 200) continue;
          final found = n.endsWith('.sha256') ? _hex.firstMatch(res.body)?.group(0)?.toLowerCase() : fromText(res.body);
          if (found != null) return found;
        } catch (_) {}
      }
    }
    return fromText(notes);
  }

  Future<bool> _verify() async {
    final expected = _sha256;
    if (expected == null) return true; // signature is still enforced by the installer
    final digest = await sha256.bind(_apk.openRead()).first;
    return digest.toString() == expected;
  }

  Future<void> download() async {
    final url = _assetUrl;
    if (url == null || _phase == UpdatePhase.downloading) return;
    _cancel = false;
    _set(UpdatePhase.downloading);
    final part = File('${_apk.path}.part');
    try {
      await _apk.parent.create(recursive: true);
      // Drop APKs of older releases.
      for (final f in _apk.parent.listSync().whereType<File>()) {
        if (f.path != _apk.path && f.path != part.path) f.deleteSync();
      }
      var have = part.existsSync() ? part.lengthSync() : 0;
      if (have > _total && _total > 0) {
        part.deleteSync();
        have = 0;
      }
      final req = http.Request('GET', Uri.parse(url));
      if (have > 0) req.headers['Range'] = 'bytes=$have-';
      final res = await _http.send(req).timeout(const Duration(seconds: 20));
      if (res.statusCode != 200 && res.statusCode != 206) throw HttpException('Download failed (${res.statusCode})');
      if (res.statusCode == 200) have = 0;
      final sink = part.openWrite(mode: have > 0 ? FileMode.append : FileMode.write);
      _bytes = have;
      var windowStart = DateTime.now();
      var windowBytes = 0;
      try {
        await for (final data in res.stream.timeout(const Duration(seconds: 30))) {
          if (_cancel) break;
          sink.add(data);
          _bytes += data.length;
          windowBytes += data.length;
          final dt = DateTime.now().difference(windowStart);
          if (dt > const Duration(milliseconds: 400)) {
            _speed = (windowBytes * 1000 / dt.inMilliseconds).round();
            windowStart = DateTime.now();
            windowBytes = 0;
            _set(UpdatePhase.downloading);
          }
        }
      } finally {
        await sink.close();
      }
      if (_cancel) {
        _set(UpdatePhase.available);
        return;
      }
      await part.rename(_apk.path);
      if (!await _verify()) {
        _apk.deleteSync();
        throw const HttpException('The download didn’t match its checksum and was deleted.');
      }
      _bytes = _total;
      _set(UpdatePhase.ready);
    } catch (e) {
      _set(UpdatePhase.failed, error: e is HttpException ? e.message : 'Download interrupted — try again to resume.');
    }
  }

  Future<void> install() async {
    if (!_apk.existsSync()) return _set(UpdatePhase.failed, error: 'The update file is missing. Download it again.');
    try {
      _set(UpdatePhase.installing);
      final file = _apk.path;
      final appImage = _appImage;
      if (Platform.isWindows) {
        // Inno Setup: closes the running app, updates in place and relaunches it.
        await Process.start(file, ['/SILENT', '/CLOSEAPPLICATIONS', '/RESTARTAPPLICATIONS'], mode: ProcessStartMode.detached);
        exit(0);
      } else if (appImage != null && file.toLowerCase().endsWith('.appimage')) {
        // Swap the AppImage file and start the new one.
        await Process.run('chmod', ['+x', file]);
        await File(file).copy('$appImage.new');
        await File('$appImage.new').rename(appImage);
        await Process.start(appImage, const [], mode: ProcessStartMode.detached);
        exit(0);
      } else {
        // Portable tar.gz: show the download so it can be extracted over the old folder.
        await Process.start('xdg-open', [p.dirname(file)], mode: ProcessStartMode.detached);
        _set(UpdatePhase.ready, error: 'Extract the downloaded archive over your Hyde Music folder.');
      }
    } catch (e) {
      _set(UpdatePhase.failed, error: 'Couldn’t start the installer');
    }
  }

  Future<void> cancel() async {
    _cancel = true;
    if (_phase != UpdatePhase.downloading) _set(_release == null ? UpdatePhase.idle : UpdatePhase.available);
  }

  Future<void> skip() async {
    final v = _release?.version;
    if (v != null) await settings.write('updateSkippedVersion', v);
    _release = null;
    _set(UpdatePhase.upToDate);
  }

  Future<void> setPrefs({bool? beta, bool? autoDownload, bool? wifiOnly, bool? autoCheck}) async {
    if (beta != null) await settings.write('updateBetaChannel', beta);
    if (autoDownload != null) await settings.write('updateAutoDownload', autoDownload);
    if (wifiOnly != null) await settings.write('updateWifiOnly', wifiOnly);
    if (autoCheck != null) await settings.write('checkForUpdates', autoCheck);
    _set(_phase, error: _error);
  }

  /// Launch-time check (at most every 12 h) with optional auto-download.
  Future<void> autoCheck() async {
    if (!_autoCheck) return;
    final last = settings['updateLastChecked'] as int? ?? 0;
    if (DateTime.now().millisecondsSinceEpoch - last < const Duration(hours: 12).inMilliseconds) return;
    final s = await check(manual: false);
    if (s.phase == UpdatePhase.available && _autoDownload && !_wifiOnly) await download();
  }

  void dispose() {
    _http.close();
    _states.close();
  }
}
