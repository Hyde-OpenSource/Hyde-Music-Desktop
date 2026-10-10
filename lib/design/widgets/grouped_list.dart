import 'package:flutter/cupertino.dart';

import '../../core/motion/hyde_motion.dart';
import '../../core/theme/hyde_theme.dart';

/// iOS inset-grouped section — the rounded cards of the Settings reference.
class GroupedSection extends StatelessWidget {
  const GroupedSection({super.key, required this.children, this.header, this.footer, this.separatorIndent = 62});

  final List<Widget> children;
  final String? header;
  final String? footer;

  /// Separators start under the title, not the icon.
  final double separatorIndent;

  @override
  Widget build(BuildContext context) {
    final sep = HydeColors.separator.resolveFrom(context);
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      rows.add(children[i]);
      if (i < children.length - 1) {
        rows.add(
          Padding(
            padding: EdgeInsetsDirectional.only(start: separatorIndent, end: 16),
            child: SizedBox(height: 0.5, child: ColoredBox(color: sep)),
          ),
        );
      }
    }
    final secondary = HydeColors.secondaryLabel.resolveFrom(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(HydeMetrics.gutter, 0, HydeMetrics.gutter, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (header != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                header!.toUpperCase(),
                style: HydeText.footnote.copyWith(color: secondary, letterSpacing: 0.3),
              ),
            ),
          ClipRSuperellipse(
            borderRadius: BorderRadius.circular(HydeMetrics.groupRadius),
            child: ColoredBox(
              color: HydeColors.groupedFill.resolveFrom(context),
              child: Column(children: rows),
            ),
          ),
          if (footer != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(footer!, style: HydeText.footnote.copyWith(color: secondary)),
            ),
        ],
      ),
    );
  }
}

/// One row in a [GroupedSection].
class GroupedRow extends StatefulWidget {
  const GroupedRow({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.iconColor,
    this.leading,
    this.trailing,
    this.value,
    this.onTap,
    this.chevron,
    this.destructive = false,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Color? iconColor;
  final Widget? leading;
  final Widget? trailing;

  /// Secondary text before the chevron (current value of a choice).
  final String? value;
  final VoidCallback? onTap;

  /// Defaults to true when [onTap] is set and there's no [trailing].
  final bool? chevron;
  final bool destructive;

  @override
  State<GroupedRow> createState() => _GroupedRowState();
}

class _GroupedRowState extends State<GroupedRow> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final label = widget.destructive
        ? CupertinoColors.systemRed.resolveFrom(context)
        : HydeColors.label.resolveFrom(context);
    final secondary = HydeColors.secondaryLabel.resolveFrom(context);
    final showChevron = widget.chevron ?? (widget.onTap != null && widget.trailing == null);

    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: HydeMetrics.rowHeight),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            if (widget.leading != null) ...[widget.leading!, const SizedBox(width: 16)],
            if (widget.icon != null) ...[
              SizedBox(width: 30, child: Icon(widget.icon, size: 27, color: widget.iconColor ?? label)),
              const SizedBox(width: 16),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(widget.title, style: HydeText.body.copyWith(fontSize: 19, color: label)),
                  if (widget.subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(widget.subtitle!, style: HydeText.footnote.copyWith(color: secondary)),
                  ],
                ],
              ),
            ),
            if (widget.value != null) ...[
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  widget.value!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: HydeText.body.copyWith(color: secondary),
                ),
              ),
            ],
            if (widget.trailing != null) ...[const SizedBox(width: 8), widget.trailing!],
            if (showChevron) ...[
              const SizedBox(width: 8),
              Icon(CupertinoIcons.chevron_forward, size: 20, color: HydeColors.tertiaryLabel.resolveFrom(context)),
            ],
          ],
        ),
      ),
    );

    if (widget.onTap == null) return row;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: HydeDurations.fast,
        color: _down ? HydeColors.separator.resolveFrom(context).withValues(alpha: 0.5) : const Color(0x00000000),
        child: row,
      ),
    );
  }
}
