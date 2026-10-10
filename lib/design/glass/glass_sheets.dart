import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../../core/motion/hyde_motion.dart';
import '../../core/theme/hyde_theme.dart';
import 'glass_style.dart';
import 'liquid_glass.dart';

/// Liquid Glass replacements for CupertinoActionSheet / CupertinoAlertDialog
/// (whose stock material is a plain blur). Same constructor shapes, so call
/// sites read the same.

class GlassSheetAction extends StatelessWidget {
  const GlassSheetAction({
    super.key,
    required this.onPressed,
    required this.child,
    this.isDefaultAction = false,
    this.isDestructiveAction = false,
  });

  final VoidCallback onPressed;
  final Widget child;
  final bool isDefaultAction;
  final bool isDestructiveAction;

  @override
  Widget build(BuildContext context) {
    final color = isDestructiveAction ? CupertinoColors.systemRed.resolveFrom(context) : HydeColors.accent;
    return _PressHighlight(
      onTap: () {
        HapticFeedback.selectionClick();
        onPressed();
      },
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 58),
        child: Center(
          child: DefaultTextStyle(
            textAlign: TextAlign.center,
            style: HydeText.body.copyWith(
              fontSize: 19,
              color: color,
              fontWeight: isDefaultAction ? FontWeight.w600 : FontWeight.w400,
            ),
            child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), child: child),
          ),
        ),
      ),
    );
  }
}

class GlassActionSheet extends StatelessWidget {
  const GlassActionSheet({super.key, this.title, this.message, this.actions = const [], this.cancelButton});

  final Widget? title;
  final Widget? message;
  final List<Widget> actions;
  final Widget? cancelButton;

  @override
  Widget build(BuildContext context) {
    final secondary = HydeColors.secondaryLabel.resolveFrom(context);
    final sep = HydeColors.separator.resolveFrom(context);
    final maxH = MediaQuery.sizeOf(context).height * 0.7;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LiquidGlass(
              radius: 30,
              style: GlassStyle.menu,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxH),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (title != null || message != null)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                          child: Column(
                            children: [
                              if (title != null)
                                DefaultTextStyle(
                                  textAlign: TextAlign.center,
                                  style: HydeText.footnote.copyWith(fontWeight: FontWeight.w600, color: secondary),
                                  child: title!,
                                ),
                              if (message != null)
                                DefaultTextStyle(
                                  textAlign: TextAlign.center,
                                  style: HydeText.footnote.copyWith(color: secondary),
                                  child: message!,
                                ),
                            ],
                          ),
                        ),
                      for (var i = 0; i < actions.length; i++) ...[
                        if (i > 0 || title != null || message != null)
                          SizedBox(height: 0.5, child: ColoredBox(color: sep)),
                        actions[i],
                      ],
                    ],
                  ),
                ),
              ),
            ),
            if (cancelButton != null) ...[
              const SizedBox(height: 8),
              LiquidGlass(
                radius: 30,
                style: GlassStyle.menu,
                child: DefaultTextStyle.merge(
                  style: const TextStyle(fontWeight: FontWeight.w600),
                  child: cancelButton!,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class GlassDialogAction extends StatelessWidget {
  const GlassDialogAction({
    super.key,
    required this.onPressed,
    required this.child,
    this.isDefaultAction = false,
    this.isDestructiveAction = false,
  });

  final VoidCallback? onPressed;
  final Widget child;
  final bool isDefaultAction;
  final bool isDestructiveAction;

  @override
  Widget build(BuildContext context) {
    final color = isDestructiveAction ? CupertinoColors.systemRed.resolveFrom(context) : HydeColors.accent;
    return Expanded(
      child: _PressHighlight(
        onTap: onPressed,
        radius: 22,
        child: SizedBox(
          height: 50,
          child: Center(
            child: DefaultTextStyle(
              style: HydeText.headline.copyWith(
                color: color,
                fontWeight: isDefaultAction ? FontWeight.w700 : FontWeight.w500,
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class GlassAlertDialog extends StatelessWidget {
  const GlassAlertDialog({super.key, this.title, this.content, this.actions = const []});

  final Widget? title;
  final Widget? content;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final label = HydeColors.label.resolveFrom(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: LiquidGlass(
            radius: 30,
            style: GlassStyle.menu,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 20, 18, 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (title != null)
                    DefaultTextStyle(
                      textAlign: TextAlign.center,
                      style: HydeText.headline.copyWith(fontSize: 18, color: label),
                      child: title!,
                    ),
                  if (content != null) ...[
                    const SizedBox(height: 8),
                    DefaultTextStyle(
                      textAlign: TextAlign.center,
                      style: HydeText.subhead.copyWith(color: label.withValues(alpha: 0.85)),
                      child: content!,
                    ),
                  ],
                  const SizedBox(height: 14),
                  Row(children: [for (final a in actions) a]),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Dialog route that animates glass correctly: spring-ish scale + the glass
/// fading via its own parameters (a FadeTransition would put the glass in an
/// offscreen layer and kill the refraction).
Future<T?> showGlassDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  return Navigator.of(context, rootNavigator: true).push<T>(
    RawDialogRoute<T>(
      barrierDismissible: barrierDismissible,
      barrierLabel: 'Dismiss',
      barrierColor: const Color(0x66000000),
      transitionDuration: HydeDurations.slow,
      pageBuilder: (context, _, _) => builder(context),
      transitionBuilder: (context, animation, _, child) {
        final t = CurvedAnimation(parent: animation, curve: Curves.easeOutBack, reverseCurve: Curves.easeInCubic);
        return ScaleTransition(scale: Tween(begin: 1.12, end: 1.0).animate(t), child: child);
      },
    ),
  );
}

class _PressHighlight extends StatefulWidget {
  const _PressHighlight({required this.child, required this.onTap, this.radius = 0});
  final Widget child;
  final VoidCallback? onTap;
  final double radius;

  @override
  State<_PressHighlight> createState() => _PressHighlightState();
}

class _PressHighlightState extends State<_PressHighlight> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.onTap == null ? null : (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: HydeDurations.fast,
        decoration: BoxDecoration(
          color: _down ? const Color(0x22FFFFFF) : const Color(0x00FFFFFF),
          borderRadius: BorderRadius.circular(widget.radius),
        ),
        child: widget.child,
      ),
    );
  }
}
