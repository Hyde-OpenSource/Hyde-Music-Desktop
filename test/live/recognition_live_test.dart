// End-to-end check of the Dart Shazam fingerprint: resolve a known song,
// decode 12 s of it with ffmpeg and ask the recognition service.
//   flutter test test/live/recognition_live_test.dart   (needs ffmpeg + network)
@Tags(['live'])
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyde_music/engine/dart/innertube.dart';
import 'package:hyde_music/engine/dart/recognition.dart';
import 'package:hyde_music/engine/dart/stream_resolver.dart';
import 'package:hyde_music/engine/dart/youtube_audio_source.dart';

void main() {
  test('recognises a song from its audio', () async {
    final resolver = StreamResolver(InnerTube());
    // "Tum Hi Ho" — Arijit Singh.
    const id = 'Umqb9KENgmk';
    final stream = await resolver.resolve(id);
    final dir = await Directory.systemTemp.createTemp('hyde_rec');
    final src = File('${dir.path}/a.webm');
    final sink = src.openWrite();
    await sink.addStream(RangedReader(resolver).read(id, 0, stream.contentLength!));
    await sink.close();

    final pcmFile = '${dir.path}/a.pcm';
    final r = await Process.run('ffmpeg', ['-y', '-ss', '60', '-t', '12', '-i', src.path, '-ac', '1', '-ar', '16000', '-f', 's16le', pcmFile]);
    expect(r.exitCode, 0, reason: '${r.stderr}');
    final bytes = await File(pcmFile).readAsBytes();
    final pcm = Int16List.sublistView(bytes, 0, bytes.length & ~1);

    final match = await ShazamClient().identifyPcm(Int16List.fromList(pcm));
    print('match: ${match?.title} — ${match?.artist} (${match?.coverUrl != null ? 'cover' : 'no cover'})');
    await dir.delete(recursive: true);
    expect(match, isNotNull);
    expect(match!.title.toLowerCase(), contains('tum hi ho'));
  }, timeout: const Timeout(Duration(minutes: 2)));
}
