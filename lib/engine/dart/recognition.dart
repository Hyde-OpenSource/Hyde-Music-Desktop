import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:record/record.dart';

import 'shazam_signature.dart';

sealed class RecognizerEvent {
  const RecognizerEvent();
}

class RecognizerLevel extends RecognizerEvent {
  const RecognizerLevel(this.level);

  /// Microphone loudness 0..1.
  final double level;
}

class RecognizerMatch extends RecognizerEvent {
  const RecognizerMatch({required this.title, required this.artist, this.coverUrl});
  final String title;
  final String artist;
  final String? coverUrl;
}

class RecognizerFailure extends RecognizerEvent {
  const RecognizerFailure(this.reason);
  final String reason;
}

/// Identifies a song from PCM audio via Shazam's discovery endpoint
/// (port of recognition/ShazamRepository.kt).
class ShazamClient {
  ShazamClient({http.Client? client}) : _http = client ?? http.Client();
  final http.Client _http;

  static const _userAgent = 'Dalvik/2.1.0 (Linux; U; Android 6.0.1; SM-G920F Build/MMB29K)';

  /// RFC 4122 version-5 (name-based, SHA-1) UUID.
  static String uuid5(List<int> namespace, String name) {
    final hash = sha1.convert([...namespace, ...utf8.encode(name)]).bytes.sublist(0, 16);
    hash[6] = (hash[6] & 0x0f) | 0x50;
    hash[8] = (hash[8] & 0x3f) | 0x80;
    final hex = hash.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  static const _nsDns = [0x6b, 0xa7, 0xb8, 0x10, 0x9d, 0xad, 0x11, 0xd1, 0x80, 0xb4, 0x00, 0xc0, 0x4f, 0xd4, 0x30, 0xc8];
  static const _nsUrl = [0x6b, 0xa7, 0xb8, 0x11, 0x9d, 0xad, 0x11, 0xd1, 0x80, 0xb4, 0x00, 0xc0, 0x4f, 0xd4, 0x30, 0xc8];

  /// [signatureUri] from [ShazamSignature.encodeUri]; null when there is no match.
  Future<RecognizerMatch?> identify(String signatureUri, int sampleMs) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final name = '${math.Random(now).nextInt(1 << 32)}';
    final uri = Uri.https(
      'amp.shazam.com',
      '/discovery/v5/en/US/android/-/tag/${uuid5(_nsDns, name).toUpperCase()}/${uuid5(_nsUrl, name)}',
      {
        'sync': 'true',
        'webv3': 'true',
        'sampling': 'true',
        'connected': '',
        'shazamapiversion': 'v3',
        'sharehub': 'true',
        'video': 'v3',
      },
    );
    final res = await _http
        .post(
          uri,
          headers: {'User-Agent': _userAgent, 'Content-Language': 'en_US', 'Content-Type': 'application/json'},
          body: jsonEncode({
            'geolocation': {'altitude': 300, 'latitude': 45, 'longitude': 2},
            'signature': {'samplems': sampleMs, 'timestamp': now, 'uri': signatureUri},
            'timestamp': now,
            'timezone': 'Europe/London',
          }),
        )
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) throw StateError('Recognition service answered ${res.statusCode}');
    final track = (jsonDecode(utf8.decode(res.bodyBytes)) as Map)['track'] as Map?;
    if (track == null) return null;
    final images = track['images'] as Map?;
    return RecognizerMatch(
      title: track['title'] as String? ?? '',
      artist: track['subtitle'] as String? ?? '',
      coverUrl: (images?['coverarthq'] ?? images?['coverart']) as String?,
    );
  }

  /// Fingerprints [pcm] (16 kHz mono s16le) off the UI thread and looks it up.
  Future<RecognizerMatch?> identifyPcm(Int16List pcm) async {
    final (uri, ms, peaks) = await Isolate.run(() {
      final sig = ShazamSignature()..process(pcm);
      return (sig.encodeUri(), sig.sampleMs, sig.peakCount);
    });
    if (peaks < 20) return null; // silence
    return identify(uri, ms);
  }

  void close() => _http.close();
}

/// Records from the microphone and identifies what is playing. Tries after
/// 5, 8 and 12 seconds of audio and stops at the first match.
class Recognizer {
  final _client = ShazamClient();

  static const _attemptsAt = [5, 8, 12];

  Stream<RecognizerEvent> listen() async* {
    final recorder = AudioRecorder();
    final Stream<Uint8List> audio;
    try {
      audio = await recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: ShazamSignature.sampleRate,
          numChannels: 1,
          autoGain: false,
          echoCancel: false,
          noiseSuppress: false,
        ),
      );
    } catch (_) {
      await recorder.dispose();
      yield const RecognizerFailure('Couldn’t start the microphone');
      return;
    }

    final pcm = BytesBuilder(copy: false);
    var attempt = 0;
    var networkError = false;
    try {
      await for (final chunk in audio) {
        pcm.add(chunk);
        yield RecognizerLevel(_level(chunk));
        final seconds = pcm.length / (2 * ShazamSignature.sampleRate);
        if (attempt < _attemptsAt.length && seconds >= _attemptsAt[attempt]) {
          attempt++;
          final bytes = pcm.toBytes();
          final samples = Int16List.sublistView(bytes, 0, bytes.length & ~1);
          try {
            final match = await _client.identifyPcm(Int16List.fromList(samples));
            if (match != null) {
              yield match;
              return;
            }
          } catch (_) {
            networkError = true;
          }
          if (attempt == _attemptsAt.length) break;
        }
      }
      yield RecognizerFailure(networkError ? 'Couldn’t reach the recognition service' : 'No match found');
    } finally {
      try {
        await recorder.stop();
      } catch (_) {}
      await recorder.dispose();
    }
  }

  /// RMS loudness of a PCM chunk, 0..1 (perceptually scaled).
  static double _level(Uint8List chunk) {
    final n = chunk.length ~/ 2;
    if (n == 0) return 0;
    final data = ByteData.sublistView(chunk);
    var sum = 0.0;
    for (var i = 0; i < n; i++) {
      final s = data.getInt16(i * 2, Endian.little) / 32768;
      sum += s * s;
    }
    return (math.sqrt(sum / n) * 6).clamp(0.0, 1.0);
  }
}
