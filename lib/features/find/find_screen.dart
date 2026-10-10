import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/motion/hyde_motion.dart';
import '../../core/theme/hyde_theme.dart';
import '../../design/glass/glass_pressable.dart';
import '../../design/glass/glass_style.dart';
import '../../design/glass/liquid_glass.dart';
import '../../design/widgets/artwork.dart';
import '../../design/widgets/large_title_scaffold.dart';
import '../../engine/models.dart';
import '../../state/providers.dart';

/// Find a song (ui/screens/FindSongScreen.kt + recognition/*): a glass orb
/// that breathes with the microphone level while the Shazam-signature engine
/// listens, then shows the match.
class FindScreen extends ConsumerStatefulWidget {
  const FindScreen({super.key});

  @override
  ConsumerState<FindScreen> createState() => _FindScreenState();
}

class _FindScreenState extends ConsumerState<FindScreen> with TickerProviderStateMixin {
  RecognitionState _state = const RecognitionIdle();
  StreamSubscription<RecognitionState>? _sub;
  late final AnimationController _level = AnimationController.unbounded(vsync: this);
  late final AnimationController _spin = AnimationController(vsync: this, duration: const Duration(seconds: 6));

  @override
  void dispose() {
    _sub?.cancel();
    _level.dispose();
    _spin.dispose();
    super.dispose();
  }

  void _toggle() {
    if (_state is RecognitionListening) {
      _sub?.cancel();
      _spin.stop();
      springTo(_level, 0, HydeSprings.bouncy);
      setState(() => _state = const RecognitionIdle());
      return;
    }
    HapticFeedback.mediumImpact();
    _spin.repeat();
    setState(() => _state = const RecognitionListening(0));
    _sub = ref.read(engineProvider).recognize().listen((s) {
      if (!mounted) return;
      if (s is RecognitionListening) springTo(_level, s.level, HydeSprings.snappy);
      if (s is RecognitionMatched || s is RecognitionFailed) {
        _spin.stop();
        springTo(_level, 0, HydeSprings.bouncy);
        HapticFeedback.heavyImpact();
      }
      setState(() => _state = s);
    });
  }

  @override
  Widget build(BuildContext context) {
    final listening = _state is RecognitionListening;
    final label = switch (_state) {
      RecognitionListening() => 'Listening…',
      RecognitionMatched() => 'Found it',
      RecognitionFailed(:final reason) => reason,
      RecognitionIdle() => 'Tap to Find',
    };

    return LargeTitleScaffold(
      title: 'Find',
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            children: [
              const SizedBox(height: 40),
              SizedBox.square(
                dimension: 280,
                child: AnimatedBuilder(
                  animation: Listenable.merge([_level, _spin]),
                  builder: (context, _) {
                    final l = _level.value;
                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        // Coloured aura the glass refracts.
                        Transform.rotate(
                          angle: _spin.value * 2 * math.pi,
                          child: Container(
                            width: 200 + 60 * l,
                            height: 200 + 60 * l,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: SweepGradient(
                                colors: [
                                  Color(0xFFFA2D48),
                                  Color(0xFFFF9F0A),
                                  Color(0xFF5E5CE6),
                                  Color(0xFF64D2FF),
                                  Color(0xFFFA2D48),
                                ],
                              ),
                            ),
                          ),
                        ),
                        GlassPressable(
                          onTap: _toggle,
                          pressedScale: 1.06,
                          child: Transform.scale(
                            scale: 1 + 0.08 * l,
                            child: LiquidGlass.capsule(
                              style: GlassStyle.clear.copyWith(blur: 18, refraction: 34, bezel: 46, dispersion: 0.8),
                              child: SizedBox.square(
                                dimension: 220,
                                child: Icon(
                                  listening ? CupertinoIcons.waveform : CupertinoIcons.music_mic,
                                  size: 78,
                                  color: const Color(0xFFFFFFFF),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 28),
              Text(label, style: HydeText.title2.copyWith(color: HydeColors.label.resolveFrom(context))),
              const SizedBox(height: 6),
              Text(
                'Identify music playing around you',
                style: HydeText.subhead.copyWith(color: HydeColors.secondaryLabel.resolveFrom(context)),
              ),
              if (_state case RecognitionMatched(:final track)) _Match(track: track),
            ],
          ),
        ),
      ],
    );
  }
}

class _Match extends ConsumerWidget {
  const _Match({required this.track});
  final Track track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(HydeMetrics.gutter, 28, HydeMetrics.gutter, 0),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: ShapeDecoration(
          color: HydeColors.groupedFill.resolveFrom(context),
          shape: RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(HydeMetrics.groupRadius)),
        ),
        child: Row(
          children: [
            Artwork(url: track.thumbnailUrl, size: 72, radius: 10),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(track.title, style: HydeText.headline.copyWith(color: HydeColors.label.resolveFrom(context))),
                  Text(
                    track.artistLine,
                    style: HydeText.subhead.copyWith(color: HydeColors.secondaryLabel.resolveFrom(context)),
                  ),
                ],
              ),
            ),
            CupertinoButton.filled(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              minimumSize: const Size(44, 40),
              borderRadius: BorderRadius.circular(20),
              onPressed: () => ref.read(engineProvider).playTracks([track]),
              child: const Text('Play'),
            ),
          ],
        ),
      ),
    );
  }
}
