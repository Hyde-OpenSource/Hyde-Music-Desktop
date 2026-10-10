import 'package:flutter/cupertino.dart';

import '../../core/theme/hyde_theme.dart';

/// iOS large-title page: a big title that scrolls away while a compact title
/// fades in next to the back chevron (Settings / Playlists references).
/// The top edge uses a soft fade instead of a hard bar (iOS 26 scroll-edge).
class LargeTitleScaffold extends StatefulWidget {
  const LargeTitleScaffold({
    super.key,
    required this.title,
    required this.slivers,
    this.actions = const [],
    this.showLargeTitle = true,
    this.bottomInset = 150,
    this.onEndReached,
    this.titleRevealOffset,
  });

  final String title;
  final List<Widget> slivers;
  final List<Widget> actions;
  final bool showLargeTitle;

  /// Room left for the floating mini player + tab bar.
  final double bottomInset;

  /// Called when the list is scrolled near its end (paging).
  final VoidCallback? onEndReached;

  /// For pages without a large title: scroll offset at which the compact
  /// title appears (e.g. once the header artwork has scrolled away).
  /// Null shows it from the start.
  final double? titleRevealOffset;

  @override
  State<LargeTitleScaffold> createState() => _LargeTitleScaffoldState();
}

class _LargeTitleScaffoldState extends State<LargeTitleScaffold> {
  final _controller = ScrollController();

  /// 0 = at rest, 1 = content is under the bar (bar background fully in).
  final _bar = ValueNotifier<double>(0);

  /// 0 = compact title hidden, 1 = shown.
  final _title = ValueNotifier<double>(0);

  // Large title block: 10 (top pad) + ~41 (34 pt line) + 14 (bottom pad).
  static const _largeTitleExtent = 65.0;

  @override
  void initState() {
    super.initState();
    _title.value = widget.showLargeTitle || widget.titleRevealOffset != null ? 0 : 1;
    _controller.addListener(_onScroll);
  }

  void _onScroll() {
    final offset = _controller.offset;
    _bar.value = (offset / 24).clamp(0.0, 1.0);
    if (widget.showLargeTitle) {
      // The compact title takes over only once the large one has slid under
      // the bar — never both at once.
      _title.value = ((offset - (_largeTitleExtent - 22)) / 16).clamp(0.0, 1.0);
    } else if (widget.titleRevealOffset != null) {
      _title.value = ((offset - widget.titleRevealOffset!) / 24).clamp(0.0, 1.0);
    }
    final end = widget.onEndReached;
    if (end != null && _controller.position.extentAfter < 600) end();
  }

  @override
  void dispose() {
    _controller.dispose();
    _bar.dispose();
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final canPop = Navigator.of(context).canPop();
    const barHeight = 48.0;
    final bg = HydeColors.background.resolveFrom(context);
    final label = HydeColors.label.resolveFrom(context);

    return ColoredBox(
      color: bg,
      child: Stack(
        children: [
          CustomScrollView(
            controller: _controller,
            physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
            slivers: [
              SliverToBoxAdapter(child: SizedBox(height: top + barHeight)),
              if (widget.showLargeTitle)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(HydeMetrics.gutter + 4, 10, HydeMetrics.gutter, 14),
                    child: Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: HydeText.largeTitle.copyWith(color: label),
                    ),
                  ),
                ),
              ...widget.slivers,
              SliverToBoxAdapter(child: SizedBox(height: widget.bottomInset + MediaQuery.paddingOf(context).bottom)),
            ],
          ),
          // Top bar: opaque behind the status bar and buttons once content
          // scrolls under it, fading out below.
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: ValueListenableBuilder<double>(
              valueListenable: _bar,
              builder: (context, p, child) => DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [bg.withValues(alpha: p), bg.withValues(alpha: 0.94 * p), bg.withValues(alpha: 0)],
                    stops: const [0, 0.78, 1],
                  ),
                ),
                child: child,
              ),
              child: Padding(
                padding: EdgeInsets.only(top: top, bottom: 14),
                child: SizedBox(
                  height: barHeight,
                  child: Row(
                    children: [
                      if (canPop)
                        CupertinoButton(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          minimumSize: const Size(44, 44),
                          onPressed: () => Navigator.of(context).maybePop(),
                          child: const Icon(CupertinoIcons.chevron_back, color: HydeColors.accent, size: 26),
                        )
                      else
                        const SizedBox(width: HydeMetrics.gutter + 4),
                      Expanded(
                        child: ValueListenableBuilder<double>(
                          valueListenable: _title,
                          builder: (context, t, child) => Opacity(opacity: t, child: child),
                          child: Text(
                            widget.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: HydeText.headline.copyWith(color: label),
                          ),
                        ),
                      ),
                      ...widget.actions,
                      const SizedBox(width: 12),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
