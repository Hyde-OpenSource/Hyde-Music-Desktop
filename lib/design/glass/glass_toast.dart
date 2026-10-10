import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../../core/motion/hyde_motion.dart';
import '../../core/theme/hyde_theme.dart';
import 'glass_style.dart';
import 'liquid_glass.dart';

/// Short glass notice that drops in under the status bar ("Couldn't play…").
void showGlassToast(BuildContext context, String message, {IconData icon = CupertinoIcons.exclamationmark_circle}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  HapticFeedback.lightImpact();
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _Toast(message: message, icon: icon, onDone: () => entry.remove()),
  );
  overlay.insert(entry);
}

/// Runs [action]; on failure shows the error as a glass toast instead of
/// failing silently.
Future<void> guarded(BuildContext context, Future<void> Function() action, {String? failure}) async {
  try {
    await action();
  } catch (e) {
    if (context.mounted) showGlassToast(context, failure ?? friendlyError(e));
  }
}

/// An error as a short sentence the user can act on.
String friendlyError(Object e) {
  final s = e.toString();
  if (s.contains('SocketException') ||
      s.contains('Failed host lookup') ||
      s.contains('TimeoutException') ||
      s.contains('ClientException') ||
      s.contains('HandshakeException')) {
    return 'No internet connection';
  }
  if (s.startsWith('Bad state: ')) return s.substring(11);
  if (s.startsWith('FormatException: ')) return s.substring(17);
  if (s.startsWith('InnerTube')) return 'YouTube Music didn’t respond — try again';
  final m = RegExp(r'PlatformException\([^,]*, ([^,]+),').firstMatch(s);
  if (m != null) return m.group(1)!;
  // Engine messages are already written for people; anything long is a stack trace.
  return s.length > 110 || s.contains('Exception') ? 'Something went wrong' : s;
}

class _Toast extends StatefulWidget {
  const _Toast({required this.message, required this.icon, required this.onDone});
  final String message;
  final IconData icon;
  final VoidCallback onDone;

  @override
  State<_Toast> createState() => _ToastState();
}

class _ToastState extends State<_Toast> with SingleTickerProviderStateMixin {
  late final AnimationController _t = AnimationController.unbounded(vsync: this);
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    springTo(_t, 1, HydeSprings.bouncy);
    _timer = Timer(const Duration(milliseconds: 2600), () async {
      await springTo(_t, 0, HydeSprings.smooth).orCancel.catchError((_) {});
      widget.onDone();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top + 8;
    return Positioned(
      top: top,
      left: HydeMetrics.gutter,
      right: HydeMetrics.gutter,
      child: AnimatedBuilder(
        animation: _t,
        builder: (context, child) => Transform.translate(
          offset: Offset(0, -80 * (1 - _t.value)),
          child: Transform.scale(scale: 0.9 + 0.1 * _t.value, child: child),
        ),
        child: Align(
          child: LiquidGlass.capsule(
            style: GlassStyle.menu,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(widget.icon, size: 20, color: const Color(0xFFFFFFFF)),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      widget.message,
                      style: HydeText.subhead.copyWith(color: const Color(0xFFFFFFFF), fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
