import 'dart:math';

import '../models.dart';

/// AI Shuffle: a shuffle that flows. Each next song is picked by how well it
/// follows the previous one (shared artist, same album, similar length), with
/// at most two songs in a row by one artist and a little randomness so no two
/// shuffles match. Same algorithm as Hyde Music for Android 6.0.
///
/// Scores at most [_sample] candidates per step, so big queues stay
/// O(n · sample) instead of O(n²).
List<Track> smartShuffle(List<Track> tracks, {Track? first, Random? random}) {
  final rand = random ?? Random();
  final pool = List.of(tracks);
  if (first != null) pool.removeWhere((t) => t.id == first.id);
  if (pool.isEmpty) return [?first];

  const sample = 192;
  const maxArtistRun = 2;
  const wildcard = 0.08;

  Set<String> artistsOf(Track t) => {for (final a in t.artists) (a.id ?? a.name.toLowerCase())};
  final artists = {for (final t in [...pool, ?first]) t.id: artistsOf(t)};
  bool shares(Track a, Track b) => artists[a.id]!.any(artists[b.id]!.contains);

  final out = <Track>[];
  var previous = first ?? pool.removeAt(rand.nextInt(pool.length));
  out.add(previous);
  var run = 1;

  double score(Track c) {
    var s = 0.0;
    if (shares(previous, c)) s += run >= maxArtistRun ? -50 : 6;
    if (previous.albumId != null && previous.albumId == c.albumId) s += 3;
    final a = previous.duration.inSeconds, b = c.duration.inSeconds;
    if (a > 0 && b > 0) s += 2 * (1 - (a - b).abs() / max(a, b));
    return s + rand.nextDouble() * 4; // jitter: equal scores don't always cluster
  }

  while (pool.isNotEmpty) {
    int pick;
    if (rand.nextDouble() < wildcard) {
      pick = rand.nextInt(pool.length);
    } else {
      // Partial Fisher–Yates: the first n slots become a random sample.
      final n = min(sample, pool.length);
      pick = 0;
      var best = double.negativeInfinity;
      for (var k = 0; k < n; k++) {
        final j = k + rand.nextInt(pool.length - k);
        final t = pool[k];
        pool[k] = pool[j];
        pool[j] = t;
        final sc = score(pool[k]);
        if (sc > best) {
          best = sc;
          pick = k;
        }
      }
    }
    final selected = pool[pick];
    pool[pick] = pool.last;
    pool.removeLast();
    run = shares(previous, selected) ? run + 1 : 1;
    out.add(selected);
    previous = selected;
  }
  return out;
}
