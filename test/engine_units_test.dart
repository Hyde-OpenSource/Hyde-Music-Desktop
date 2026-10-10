import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyde_music/engine/dart/dart_engine.dart' show parseYouTubeLink;
import 'package:hyde_music/engine/dart/lastfm.dart';
import 'package:hyde_music/engine/dart/listen_together_proto.dart';
import 'package:hyde_music/engine/dart/lyrics.dart';
import 'package:hyde_music/engine/dart/settings_store.dart';
import 'package:hyde_music/engine/dart/shazam_signature.dart';
import 'package:hyde_music/engine/dart/updater.dart';
import 'package:hyde_music/engine/dart/yt_parser.dart';
import 'package:hyde_music/engine/models.dart';

void main() {
  group('YouTube links', () {
    test('videos, playlists, albums, artists, search', () {
      expect(parseYouTubeLink('https://music.youtube.com/watch?v=abc123&list=PLx')!, (type: 'video', id: 'abc123', playlistId: 'PLx'));
      expect(parseYouTubeLink('https://youtu.be/abc123?si=x')!.id, 'abc123');
      expect(parseYouTubeLink('vnd.youtube:abc123')!.type, 'video');
      expect(parseYouTubeLink('https://www.youtube.com/playlist?list=PL42')!, (type: 'playlist', id: 'PL42', playlistId: null));
      expect(parseYouTubeLink('https://music.youtube.com/browse/MPREb_1')!.type, 'album');
      expect(parseYouTubeLink('https://music.youtube.com/channel/UCabc')!.type, 'artist');
      expect(parseYouTubeLink('https://music.youtube.com/search?q=tum+hi+ho')!, (type: 'search', id: 'tum hi ho', playlistId: null));
      expect(parseYouTubeLink('https://example.com/watch?v=1'), isNull);
      expect(parseYouTubeLink('just some text'), isNull);
    });
  });

  group('InnerTube parser', () {
    test('song row: artists, album, duration, explicit by endpoint type', () {
      Map<String, Object?> run(String text, {String? browseId, String? pageType}) => {
        'text': text,
        if (browseId != null)
          'navigationEndpoint': {
            'browseEndpoint': {
              'browseId': browseId,
              'browseEndpointContextSupportedConfigs': {
                'browseEndpointContextMusicConfig': {'pageType': pageType},
              },
            },
          },
      };
      Map<String, Object?> col(List<Map<String, Object?>> runs) => {
        'musicResponsiveListItemFlexColumnRenderer': {
          'text': {'runs': runs},
        },
      };
      final item = Yt.item({
        'musicResponsiveListItemRenderer': {
          'playlistItemData': {'videoId': 'vid1'},
          'flexColumns': [
            col([run('Raabta')]),
            col([
              run('Arijit Singh', browseId: 'UC1', pageType: 'MUSIC_PAGE_TYPE_ARTIST'),
              run(' & '),
              run('Pritam', browseId: 'UC2', pageType: 'MUSIC_PAGE_TYPE_ARTIST'),
              run(' • '),
              run('Agent Vinod', browseId: 'MPREb_9', pageType: 'MUSIC_PAGE_TYPE_ALBUM'),
              run(' • '),
              run('4:04'),
            ]),
          ],
          'badges': [
            {
              'musicInlineBadgeRenderer': {
                'icon': {'iconType': 'MUSIC_EXPLICIT_BADGE'},
              },
            },
          ],
          'thumbnail': {
            'musicThumbnailRenderer': {
              'thumbnail': {
                'thumbnails': [
                  {'url': 'https://lh3.googleusercontent.com/abc=w60-h60-l90-rj'},
                ],
              },
            },
          },
        },
      });
      final t = (item as TrackItem).track;
      expect(t.id, 'vid1');
      expect(t.artistLine, 'Arijit Singh, Pritam');
      expect(t.albumId, 'MPREb_9');
      expect(t.duration, const Duration(minutes: 4, seconds: 4));
      expect(t.explicit, isTrue);
      expect(t.thumbnailUrl, endsWith('=w544-h544-l90-rj'));
    });

    test('durations', () {
      expect(Yt.parseDuration('3:21'), const Duration(minutes: 3, seconds: 21));
      expect(Yt.parseDuration('1:00:52'), const Duration(hours: 1, seconds: 52));
      expect(Yt.parseDuration('Song'), Duration.zero);
    });
  });

  group('lyrics', () {
    test('LRC with repeated stamps, metadata and word tags', () {
      final l = LyricsService.parse('[ar:Someone]\n[00:12.50][00:40.00]Hello there\n[00:20.000]<00:20.00>Two <00:20.60>words\nplain line');
      expect(l.synced, isTrue);
      expect(l.lines.map((e) => e.start.inMilliseconds), [12500, 20000, 40000]);
      expect(l.lines[1].text, 'Two words');
      expect(l.lines[1].words.length, 2);
    });

    test('plain text stays unsynced; marker means none', () {
      expect(LyricsService.parse('one\ntwo').synced, isFalse);
      expect(LyricsService.parse(LyricsService.notFound).lines, isEmpty);
    });

    test('title cleanup', () {
      expect(LyricsService.cleanTitle('Tum Hi Ho (From "Aashiqui 2")'), 'Tum Hi Ho');
      expect(LyricsService.cleanTitle('Song Name [Official Video]'), 'Song Name');
      expect(LyricsService.cleanTitle('Song feat. Someone'), 'Song');
    });
  });

  test('updater compares versions', () {
    expect(Updater.compareVersions('v5.1', '5.0.9'), greaterThan(0));
    expect(Updater.compareVersions('5.0.0', '5.0'), 0);
    expect(Updater.compareVersions('v4.9.9-beta2', '5.0.0'), lessThan(0));
  });

  test('Last.fm signature is md5 of sorted params + secret', () {
    // md5("api_keyKmethodauth.getMobileSessionpasswordPusernameUsecret")
    expect(
      LastFm.signature({'method': 'auth.getMobileSession', 'username': 'U', 'password': 'P', 'api_key': 'K'}, 'secret'),
      matches(RegExp(r'^[0-9a-f]{32}$')),
    );
    expect(LastFm.signature({'b': '2', 'a': '1'}, 's'), LastFm.signature({'a': '1', 'b': '2'}, 's'));
  });

  test('DataStore preferences file decodes every value type', () {
    // PreferenceMap{ "on": bool true, "n": int 7, "name": string "hi", "set": {a,b}, "f": float 1.5 }
    List<int> entry(String key, List<int> value) {
      final k = key.codeUnits;
      final body = [0x0a, k.length, ...k, 0x12, value.length, ...value];
      return [0x0a, body.length, ...body];
    }

    final bytes = Uint8List.fromList([
      ...entry('on', [0x08, 0x01]),
      ...entry('n', [0x18, 0x07]),
      ...entry('name', [0x2a, 0x02, 0x68, 0x69]),
      ...entry('set', [0x32, 0x06, 0x0a, 0x01, 0x61, 0x0a, 0x01, 0x62]),
      ...entry('f', [0x15, 0x00, 0x00, 0xc0, 0x3f]),
    ]);
    expect(SettingsStore.decodeDataStore(bytes), {'on': true, 'n': 7, 'name': 'hi', 'set': ['a', 'b'], 'f': 1.5});
  });

  test('Listen Together protobuf round-trips nested and repeated fields', () {
    final frame = LtProto.encode('playback_action', {
      'action': 'change_track',
      'track_id': 'vid',
      'position': 123456,
      'track_info': {'id': 'vid', 'title': 'Tïtle', 'artist': 'A', 'duration': 200000, 'thumbnail': 'https://t'},
      'queue': [
        {'id': 'q1', 'title': 'One'},
        {'id': 'q2', 'title': 'Two'},
      ],
    });
    final (type, payload) = LtProto.decode(frame);
    expect(type, 'playback_action');
    expect(payload['action'], 'change_track');
    expect(payload['position'], 123456);
    expect((payload['track_info'] as Map)['title'], 'Tïtle');
    expect((payload['queue'] as List).map((q) => (q as Map)['id']), ['q1', 'q2']);
    // A message without payload is just the envelope type.
    expect(LtProto.decode(LtProto.encode('leave_room')).$1, 'leave_room');
  });

  test('Shazam signature has the documented header and a valid CRC', () {
    // One second of a 1 kHz tone: enough to exercise the FFT and encoder.
    final pcm = Int16List(16000 * 3);
    for (var i = 0; i < pcm.length; i++) {
      pcm[i] = (12000 * ((i ~/ 8).isEven ? 1 : -1)).toInt();
    }
    final sig = ShazamSignature()..process(pcm);
    final bytes = sig.encodeBinary();
    final data = ByteData.sublistView(bytes);
    expect(data.getUint32(0, Endian.little), 0xcafe2580);
    expect(data.getUint32(12, Endian.little), 0x94119c00);
    expect(data.getUint32(8, Endian.little), bytes.length - 48);
    expect(data.getUint32(4, Endian.little), ShazamSignature.crc32(Uint8List.sublistView(bytes, 8)));
    expect(ShazamSignature.crc32(Uint8List.fromList('123456789'.codeUnits)), 0xcbf43926);
    expect(sig.sampleMs, 3000);
    expect(sig.encodeUri(), startsWith('data:audio/vnd.shazam.sig;base64,'));
  });
}
