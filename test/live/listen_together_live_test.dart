// Two clients against the real Listen Together server: host creates a room,
// guest joins, host changes track and plays → the guest's player follows.
@Tags(['live'])
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyde_music/engine/dart/listen_together.dart';
import 'package:hyde_music/engine/models.dart';

class FakePlayer implements ListenTogetherPlayer {
  final _c = StreamController<PlaybackSnapshot>.broadcast();
  PlaybackSnapshot _s = const PlaybackSnapshot();
  final calls = <String>[];

  void set(PlaybackSnapshot s) {
    _s = s;
    _c.add(s);
  }

  @override
  PlaybackSnapshot get current => _s;
  @override
  Stream<PlaybackSnapshot> get snapshots => _c.stream;
  @override
  Future<void> prepareTrack(Track track) async {
    calls.add('prepare:${track.id}');
    set(PlaybackSnapshot(track: track, queue: [track]));
  }

  @override
  Future<void> play() async {
    calls.add('play');
    set(_s.copyWith(isPlaying: true));
  }

  @override
  Future<void> pause() async {
    calls.add('pause');
    set(_s.copyWith(isPlaying: false));
  }

  @override
  Future<void> seek(Duration position) async {
    calls.add('seek:${position.inSeconds}');
    set(_s.copyWith(position: position));
  }

  @override
  Future<void> addToQueue(List<Track> tracks) async => calls.add('queue:${tracks.first.id}');
  @override
  Future<void> playNext(List<Track> tracks) async => calls.add('next:${tracks.first.id}');
}

Future<void> until(bool Function() ok, String what, {Duration timeout = const Duration(seconds: 90)}) async {
  final end = DateTime.now().add(timeout);
  while (!ok()) {
    if (DateTime.now().isAfter(end)) fail('timed out waiting for $what');
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
}

void main() {
  test('host and guest stay in sync', () async {
    Map<String, Object?> hostState = {}, guestState = {};
    final hostPlayer = FakePlayer(), guestPlayer = FakePlayer();
    final host = ListenTogether(
      player: hostPlayer,
      setting: (k) => k == 'listenTogetherAutoApproval' ? true : null,
      emit: (s) => hostState = s,
      saveBlocked: (_) async {},
    );
    final guest = ListenTogether(player: guestPlayer, setting: (_) => null, emit: (s) => guestState = s, saveBlocked: (_) async {});

    host.createRoom('HostTest');
    // The server sleeps when idle; the first connection can take a while.
    await until(() => hostState['room'] != null, 'room creation');
    final code = (hostState['room'] as Map)['code'] as String;
    print('room $code as ${hostState['role']}');
    expect(hostState['role'], 'HOST');

    guest.joinRoom(code, 'GuestTest');
    await until(() => guestState['room'] != null, 'guest join');
    expect(guestState['role'], 'GUEST');
    await until(() => ((hostState['room'] as Map)['users'] as List).length == 2, 'host seeing the guest');

    const track = Track(id: 'Umqb9KENgmk', title: 'Tum Hi Ho', artists: [ArtistRef(id: null, name: 'Arijit Singh')], duration: Duration(seconds: 262));
    hostPlayer.set(const PlaybackSnapshot(track: track, queue: [track]));
    await until(() => guestPlayer.calls.contains('prepare:Umqb9KENgmk'), 'guest loading the track');
    // Everyone buffered → the host is told to start, and the guest follows.
    await until(() => hostPlayer.calls.contains('play'), 'host start after buffering');
    await until(() => guestPlayer.calls.contains('play'), 'guest play');

    // A user pauses a moment later (changes made while a remote action is
    // being applied are deliberately not echoed back).
    await Future<void>.delayed(const Duration(seconds: 2));
    hostPlayer.set(hostPlayer.current.copyWith(isPlaying: false, position: const Duration(seconds: 2)));
    await until(() => guestPlayer.calls.contains('pause'), 'guest pause');

    print('guest calls: ${guestPlayer.calls}');
    print('host calls: ${hostPlayer.calls}');

    guest.leaveRoom();
    host.leaveRoom();
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }, timeout: const Timeout(Duration(minutes: 4)));
}
