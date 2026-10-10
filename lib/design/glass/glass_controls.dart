import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../../core/theme/hyde_theme.dart';
import 'glass_style.dart';
import 'liquid_glass.dart';

/// Circular glass button (toolbar actions, compact tab-bar ends).
/// Pressing it turns the glass from [GlassStyle.bar] toward [GlassStyle.clear],
/// the way iOS 26 controls "lift" into a lens under the finger.
class GlassIconButton extends StatelessWidget {
  const GlassIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.size = 48,
    this.iconSize = 22,
    this.color,
    this.style = GlassStyle.bar,
    this.semanticLabel,
    this.opacity = 1,
  });

  /// Fades glass and icon together (never wrap glass in `Opacity`).
  final double opacity;

  final IconData icon;
  final VoidCallback? onPressed;
  final double size;
  final double iconSize;
  final Color? color;
  final GlassStyle style;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onPressed!();
              },
        child: LiquidGlass.capsule(
          style: style,
          opacity: opacity,
          flex: onPressed != null,
          child: SizedBox.square(
            dimension: size,
            child: Icon(icon, size: iconSize, color: color ?? HydeColors.label.resolveFrom(context)),
          ),
        ),
      ),
    );
  }
}

/// Glass capsule with icon + label (e.g. "Downloads" in Library's toolbar).
class GlassPillButton extends StatelessWidget {
  const GlassPillButton({super.key, required this.icon, required this.label, required this.onPressed, this.color});

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? HydeColors.accent;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onPressed == null
          ? null
          : () {
              HapticFeedback.selectionClick();
              onPressed!();
            },
      child: LiquidGlass.capsule(
        style: GlassStyle.bar,
        flex: onPressed != null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: c),
              const SizedBox(width: 6),
              Text(label, style: HydeText.headline.copyWith(color: c)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Search field. The reference uses a flat dark capsule (not refractive) for
/// in-content fields — glass is reserved for floating chrome — so this is a
/// filled capsule; pass [glass] for a floating variant.
class HydeSearchField extends StatefulWidget {
  const HydeSearchField({
    super.key,
    required this.placeholder,
    this.controller,
    this.onChanged,
    this.onSubmitted,
    this.leading,
    this.trailing = const [],
    this.glass = false,
    this.autofocus = false,
  });

  final String placeholder;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final Widget? leading;
  final List<Widget> trailing;
  final bool glass;
  final bool autofocus;

  @override
  State<HydeSearchField> createState() => _HydeSearchFieldState();
}

class _HydeSearchFieldState extends State<HydeSearchField> {
  @override
  Widget build(BuildContext context) {
    final secondary = HydeColors.secondaryLabel.resolveFrom(context);
    final field = SizedBox(
      height: 52,
      child: Row(
        children: [
          const SizedBox(width: 14),
          widget.leading ?? Icon(CupertinoIcons.search, size: 22, color: secondary),
          const SizedBox(width: 10),
          Expanded(
            child: CupertinoTextField.borderless(
              controller: widget.controller,
              autofocus: widget.autofocus,
              placeholder: widget.placeholder,
              placeholderStyle: HydeText.body.copyWith(color: secondary),
              style: HydeText.body.copyWith(color: HydeColors.label.resolveFrom(context)),
              cursorColor: HydeColors.accent,
              onChanged: widget.onChanged,
              onSubmitted: widget.onSubmitted,
              textInputAction: TextInputAction.search,
              padding: EdgeInsets.zero,
            ),
          ),
          ...widget.trailing,
          const SizedBox(width: 8),
        ],
      ),
    );
    if (widget.glass) return LiquidGlass.capsule(style: GlassStyle.bar, child: field);
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: HydeColors.groupedFill.resolveFrom(context),
        shape: StadiumBorder(side: BorderSide(color: HydeColors.separator.resolveFrom(context), width: 0.5)),
      ),
      child: field,
    );
  }
}
