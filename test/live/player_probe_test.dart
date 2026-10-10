@Tags(['live'])
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:hyde_music/engine/dart/yt_parser.dart';

Future<String?> visitor() async {
  final r = await http.get(
    Uri.parse('https://www.youtube.com/sw.js_data'),
    headers: {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:140.0) Gecko/20100101 Firefox/140.0'},
  );
  final m = RegExp(r'"(Cg[t|s][A-Za-z0-9_%-]{20,})"').firstMatch(r.body);
  return m?.group(1);
}

/// Which clients hand out URLs that serve the whole file without a PoToken.
void main() {
  const id = 'Umqb9KENgmk';

  test('clients', () async {
    final vd = await visitor();
    print('visitor: $vd');
    final clients = <String, (Map<String, Object?>, String, String)>{
      'android_vr 1.65.10': (
        {
          'clientName': 'ANDROID_VR',
          'clientVersion': '1.65.10',
          'deviceMake': 'Oculus',
          'deviceModel': 'Quest 3',
          'androidSdkVersion': 32,
          'osName': 'Android',
          'osVersion': '12L',
        },
        'com.google.android.apps.youtube.vr.oculus/1.65.10 (Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip',
        '28',
      ),
      'tv': (
        {'clientName': 'TVHTML5', 'clientVersion': '7.20260114.12.00'},
        'Mozilla/5.0 (ChromiumStylePlatform) Cobalt/25.lts.30.1034943-gold (unlike Gecko), Unknown_TV_Unknown_0/Unknown (Unknown, Unknown)',
        '7',
      ),
      'tv_downgraded': (
        {'clientName': 'TVHTML5', 'clientVersion': '5.20260114'},
        'Mozilla/5.0 (ChromiumStylePlatform) Cobalt/Version',
        '7',
      ),
      'web_embedded': (
        {'clientName': 'WEB_EMBEDDED_PLAYER', 'clientVersion': '1.20260115.01.00'},
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36',
        '56',
      ),
      'android_music': (
        {
          'clientName': 'ANDROID_MUSIC',
          'clientVersion': '8.26.51',
          'osName': 'Android',
          'osVersion': '14',
        },
        'com.google.android.apps.youtube.music/8.26.51 (Linux; U; Android 14) gzip',
        '21',
      ),
      'android_testsuite': (
        {'clientName': 'ANDROID_TESTSUITE', 'clientVersion': '1.9', 'osName': 'Android', 'osVersion': '14'},
        'com.google.android.youtube/1.9 (Linux; U; Android 14) gzip',
        '30',
      ),
      'visionos': (
        {
          'clientName': 'VISIONOS',
          'clientVersion': '0.1',
          'osName': 'visionOS',
          'osVersion': '1.3.21O771',
          'deviceMake': 'Apple',
          'deviceModel': 'RealityDevice14,1',
        },
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15',
        '101',
      ),
    };
    for (final withVisitor in [true, false]) {
      for (final e in clients.entries) {
        final (client, ua, cid) = e.value;
        try {
          final res = await http
              .post(
                Uri.parse('https://www.youtube.com/youtubei/v1/player?prettyPrint=false'),
                headers: {
                  'Content-Type': 'application/json',
                  'User-Agent': ua,
                  'X-YouTube-Client-Name': cid,
                  'X-YouTube-Client-Version': client['clientVersion'] as String,
                  if (withVisitor && vd != null) 'X-Goog-Visitor-Id': vd,
                },
                body: jsonEncode({
                  'context': {
                    'client': {...client, 'hl': 'en', 'gl': 'US', if (withVisitor && vd != null) 'visitorData': vd},
                    if (e.key == 'web_embedded') 'thirdParty': {'embedUrl': 'https://www.youtube.com/'},
                  },
                  'videoId': id,
                  'contentCheckOk': true,
                  'racyCheckOk': true,
                }),
              )
              .timeout(const Duration(seconds: 15));
          final j = jsonDecode(res.body) as Map<String, Object?>;
          final audio = [
            for (final f in Yt.list(j, ['streamingData', 'adaptiveFormats']))
              if (((f as Map)['mimeType'] as String).startsWith('audio/')) f,
          ];
          final f = audio.where((f) => f['itag'] == 251 || f['itag'] == 140).firstOrNull;
          var line = '${withVisitor ? 'V ' : '- '}${e.key}: ${res.statusCode} ${Yt.dig(j, ['playabilityStatus', 'status'])} '
              '${'${Yt.dig(j, ['playabilityStatus', 'reason']) ?? ''}'.split('.').first} audio=${audio.length} '
              'url=${f?['url'] != null} cipher=${f?['signatureCipher'] != null} hls=${Yt.dig(j, ['streamingData', 'hlsManifestUrl']) != null} '
              'sabr=${Yt.dig(j, ['streamingData', 'serverAbrStreamingUrl']) != null}';
          if (f?['url'] != null) {
            final len = int.parse(f!['contentLength'] as String);
            final at = len - 200000;
            final rq = http.Request('GET', Uri.parse(f['url'] as String))
              ..headers.addAll({'User-Agent': ua, 'Range': 'bytes=$at-${at + 65535}'});
            final rr = await http.Client().send(rq).timeout(const Duration(seconds: 10));
            final n = await rr.stream.fold<int>(0, (a, b) => a + b.length).timeout(const Duration(seconds: 20));
            line += '  TAIL RANGE -> ${rr.statusCode} $n bytes';
          }
          print(line);
        } catch (err) {
          print('${e.key}: ERROR ${'$err'.split('\n').first}');
        }
      }
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
