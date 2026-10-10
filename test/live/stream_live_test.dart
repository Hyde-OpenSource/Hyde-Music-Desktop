@Tags(['live'])
library;


import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:hyde_music/engine/dart/innertube.dart';
import 'package:hyde_music/engine/dart/stream_resolver.dart';

void main() {
  test('resolves and downloads whole tracks in ranged chunks', () async {
    final resolver = StreamResolver(InnerTube())..log = print;
    final client = http.Client();
    // Tum Hi Ho, Raabta, a music video, an OMV.
    for (final id in ['Umqb9KENgmk', 'zlt38OOqwDc', 'kJQP7kiw5Fk', 'BddP6PYo2gs']) {
      final sw = Stopwatch()..start();
      final s = await resolver.resolve(id);
      final resolveMs = sw.elapsedMilliseconds;
      final len = s.contentLength!;
      var got = 0;
      const chunk = 256 * 1024;
      for (var at = 0; at < len; at += chunk) {
        final csw = Stopwatch()..start();
        final end = (at + chunk - 1).clamp(0, len - 1);
        final req = http.Request('GET', s.url)..headers.addAll({...s.headers, 'Range': 'bytes=$at-$end'});
        final res = await client.send(req).timeout(const Duration(seconds: 15));
        expect(res.statusCode, 206, reason: 'range $at-$end');
        got += await res.stream.fold<int>(0, (a, b) => a + b.length).timeout(const Duration(seconds: 30));
        if (at < chunk * 4) print('   chunk @$at ${csw.elapsedMilliseconds}ms');
      }
      print('$id ${s.format.label} len=$len got=$got resolve=${resolveMs}ms total=${sw.elapsedMilliseconds}ms');
      expect(got, len);
    }
    client.close();
  }, timeout: const Timeout(Duration(minutes: 3)));
}
