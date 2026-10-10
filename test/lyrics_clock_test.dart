import 'package:flutter_test/flutter_test.dart';
import 'package:hyde_music/features/player/lyrics_clock.dart';

void main() {
  test('extrapolates while playing, holds while paused, caps at one second', () async {
    final clock = LyricsClock();
    clock.report(const Duration(seconds: 10), true);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(clock.now.inMilliseconds, inInclusiveRange(10150, 10400));

    clock.report(const Duration(seconds: 20), false);
    final paused = clock.now;
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(clock.now, paused);

    clock.report(const Duration(seconds: 30), true);
    await Future<void>.delayed(const Duration(milliseconds: 1300));
    expect(clock.now, const Duration(seconds: 31)); // stalled stream: no racing ahead
    clock.dispose();
  });

  test('small lag is smoothed; seeks and play/pause notify', () {
    final clock = LyricsClock();
    var jumps = 0;
    clock.addListener(() => jumps++);
    clock.report(const Duration(seconds: 5), true); // play
    expect(jumps, 1);
    final before = clock.now;
    clock.report(before - const Duration(milliseconds: 60), true); // report latency
    expect(clock.now >= before, isTrue, reason: 'never twitches backwards for tiny lag');
    expect(jumps, 1);
    clock.report(const Duration(minutes: 2), true); // seek
    expect(jumps, 2);
    expect(clock.now.inSeconds, 120);
    clock.report(const Duration(minutes: 2), false); // pause
    expect(jumps, 3);
    clock.dispose();
  });
}
