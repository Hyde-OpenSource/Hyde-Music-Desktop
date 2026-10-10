import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../../core/motion/hyde_motion.dart';
import '../../core/theme/hyde_theme.dart';
import 'glass_style.dart';
import 'liquid_glass.dart';

class GlassMenuAction {
  const GlassMenuAction({
    required this.icon,
    required this.label,
    required this.onSelected,
    this.subtitle,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback onSelected;
  final bool destructive;
}

/// Context menu content: an optional row of big quick actions on top
/// (Favorite / Share in the reference), then grouped rows.
class GlassMenu {
  const GlassMenu({this.quickActions = const [], required this.sections});
  final List<GlassMenuAction> quickActions;
  final List<List<GlassMenuAction>> sections;

  static const _quickHeight = 96.0;
  static const _rowHeight = 56.0;
  static const _rowWithSubtitleHeight = 70.0;
  static const _divider = 17.0;
  static const _padding = 10.0;

  double get height {
    var h = _padding * 2;
    if (quickActions.isNotEmpty) h += _quickHeight + _divider;
    for (var i = 0; i < sections.length; i++) {
      for (final a in sections[i]) {
        h += a.subtitle == null ? _rowHeight : _rowWithSubtitleHeight;
      }
      if (i < sections.length - 1) h += _divider;
    }
    return h;
  }
}

/// Shows [menu] as a Liquid Glass popover that grows out of [anchor]
/// (a global rect, usually the ••• button). Resolves when dismissed.
Future<void> showGlassMenu(BuildContext context, {required Rect anchor, required GlassMenu menu}) {
  final overlay = Overlay.of(context, rootOverlay: true);
  late final OverlayEntry entry;
  final done = Completer<void>();
  entry = OverlayEntry(
    builder: (_) => _GlassMenuOverlay(
      anchor: anchor,
      menu: menu,
      onDismissed: () {
        entry.remove();
        done.complete();
      },
    ),
  );
  HapticFeedback.mediumImpact();
  overlay.insert(entry);
  return done.future;
}

Rect globalRectOf(BuildContext context) {
  final box = context.findRenderObject()! as RenderBox;
  return box.localToGlobal(Offset.zero) & box.size;
}

class _GlassMenuOverlay extends StatefulWidget {
  const _GlassMenuOverlay({required this.anchor, required this.menu, required this.onDismissed});
  final Rect anchor;
  final GlassMenu menu;
  final VoidCallback onDismissed;

  @override
  State<_GlassMenuOverlay> createState() => _GlassMenuOverlayState();
}

class _GlassMenuOverlayState extends State<_GlassMenuOverlay> with SingleTickerProviderStateMixin {
  late final AnimationController _t = AnimationController.unbounded(vsync: this);
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    springTo(_t, 1, HydeSprings.bouncy);
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  Future<void> _close([VoidCallback? then]) async {
    if (_closing) return;
    _closing = true;
    await springTo(_t, 0, HydeSprings.smooth).orCancel.catchError((_) {});
    widget.onDismissed();
    then?.call();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final screen = mq.size;
    final pad = mq.padding;
    final width = math.min(screen.width - 2 * HydeMetrics.gutter, 300.0);
    final height = math.min(widget.menu.height, screen.height - pad.vertical - 32);

    final below = widget.anchor.bottom + 8 + height <= screen.height - pad.bottom - 16;
    var top = below ? widget.anchor.bottom + 8 : widget.anchor.top - 8 - height;
    top = top.clamp(pad.top + 8, screen.height - pad.bottom - 16 - height);
    var left = widget.anchor.right - width;
    left = left.clamp(HydeMetrics.gutter, screen.width - HydeMetrics.gutter - width);
    final rect = Rect.fromLTWH(left, top, width, height);

    // Grow from the anchor's centre.
    final origin = Alignment(
      ((widget.anchor.center.dx - rect.left) / rect.width * 2 - 1).clamp(-1.0, 1.0),
      ((widget.anchor.center.dy - rect.top) / rect.height * 2 - 1).clamp(-1.0, 1.0),
    );

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: _close),
        ),
        Positioned.fromRect(
          rect: rect,
          child: AnimatedBuilder(
            animation: _t,
            builder: (context, child) {
              final v = _t.value;
              final appear = v.clamp(0.0, 1.0);
              // Jelly: height lags width a touch, both overshoot with the spring.
              final sx = 0.25 + 0.75 * v;
              final sy = 0.15 + 0.85 * math.pow(appear, 1.25) + (v - appear);
              return Transform(
                alignment: origin,
                transform: Matrix4.diagonal3Values(sx, sy, 1),
                child: LiquidGlass(
                  radius: 34,
                  style: GlassStyle.menu,
                  opacity: appear,
                  child: Opacity(opacity: ((appear - 0.35) / 0.65).clamp(0.0, 1.0), child: child),
                ),
              );
            },
            child: _MenuBody(menu: widget.menu, onSelect: (a) => _close(a.onSelected)),
          ),
        ),
      ],
    );
  }
}

class _MenuBody extends StatelessWidget {
  const _MenuBody({required this.menu, required this.onSelect});
  final GlassMenu menu;
  final ValueChanged<GlassMenuAction> onSelect;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    if (menu.quickActions.isNotEmpty) {
      children.add(
        SizedBox(
          height: GlassMenu._quickHeight,
          child: Row(
            children: [
              for (final a in menu.quickActions)
                Expanded(
                  child: _Highlight(
                    onTap: () => onSelect(a),
                    radius: 22,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(a.icon, size: 28, color: const Color(0xFFFFFFFF)),
                        const SizedBox(height: 8),
                        Text(
                          a.label,
                          style: HydeText.subhead.copyWith(fontWeight: FontWeight.w600, color: const Color(0xFFFFFFFF)),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
      children.add(const _Divider());
    }
    for (var i = 0; i < menu.sections.length; i++) {
      for (final a in menu.sections[i]) {
        children.add(_MenuRow(action: a, onTap: () => onSelect(a)));
      }
      if (i < menu.sections.length - 1) children.add(const _Divider());
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: GlassMenu._padding, horizontal: 8),
      child: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        child: Column(mainAxisSize: MainAxisSize.min, children: children),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.action, required this.onTap});
  final GlassMenuAction action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = action.destructive ? const Color(0xFFFF453A) : const Color(0xFFFFFFFF);
    return _Highlight(
      onTap: onTap,
      radius: 18,
      child: SizedBox(
        height: action.subtitle == null ? GlassMenu._rowHeight : GlassMenu._rowWithSubtitleHeight,
        child: Row(
          children: [
            const SizedBox(width: 14),
            SizedBox(width: 28, child: Icon(action.icon, size: 24, color: color)),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    action.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: HydeText.body.copyWith(fontSize: 18, color: color),
                  ),
                  if (action.subtitle != null)
                    Text(
                      action.subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: HydeText.subhead.copyWith(color: const Color(0xCCFFFFFF)),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
          ],
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
    child: SizedBox(
      height: 1,
      width: double.infinity,
      child: ColoredBox(color: Color(0x33FFFFFF)),
    ),
  );
}

class _Highlight extends StatefulWidget {
  const _Highlight({required this.child, required this.onTap, required this.radius});
  final Widget child;
  final VoidCallback onTap;
  final double radius;

  @override
  State<_Highlight> createState() => _HighlightState();
}

class _HighlightState extends State<_Highlight> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: () {
        HapticFeedback.selectionClick();
        widget.onTap();
      },
      child: AnimatedContainer(
        duration: HydeDurations.fast,
        decoration: BoxDecoration(
          color: _down ? const Color(0x24FFFFFF) : const Color(0x00FFFFFF),
          borderRadius: BorderRadius.circular(widget.radius),
        ),
        child: widget.child,
      ),
    );
  }
}
