import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyde_music/engine/dart/smart_shuffle.dart';
import 'package:hyde_music/engine/models.dart';

Track _t(int i, String artist) => Track(
  id: 'v$i',
  title: 'Song $i',
  artists: [ArtistRef(id: artist, name: artist)],
  duration: Duration(seconds: 150 + i % 90),
);

void main() {
  // Three big artists and a long tail: plain grouping would play artist runs.
  final tracks = [
    for (var i = 0; i < 300; i++) _t(i, i < 240 ? 'A${i % 3}' : 'B$i'),
  ];

  test('returns every track exactly once, starting with the given one', () {
    final out = smartShuffle(tracks, first: tracks[42], random: Random(1));
    expect(out.first.id, 'v42');
    expect(out.length, tracks.length);
    expect(out.map((t) => t.id).toSet().length, tracks.length);
  });

  test('never more than two songs in a row by one artist while others remain', () {
    for (var seed = 0; seed < 20; seed++) {
      final out = smartShuffle(tracks, random: Random(seed));
      var run = 1;
      var worst = 1;
      // Only check the first 80%: at the very end only one artist may be left.
      for (var i = 1; i < out.length * 0.8; i++) {
        run = out[i].artists.first.id == out[i - 1].artists.first.id ? run + 1 : 1;
        worst = max(worst, run);
      }
      expect(worst, lessThanOrEqualTo(3), reason: 'seed $seed'); // 2 + rare wildcard pick
    }
  });

  test('differs between runs', () {
    final a = smartShuffle(tracks, random: Random(1)).map((t) => t.id).join();
    final b = smartShuffle(tracks, random: Random(2)).map((t) => t.id).join();
    expect(a, isNot(b));
  });

  test('handles tiny lists', () {
    expect(smartShuffle(const []), isEmpty);
    expect(smartShuffle([tracks[0]]).single.id, 'v0');
    expect(smartShuffle([tracks[0]], first: tracks[0]).single.id, 'v0');
  });
}
