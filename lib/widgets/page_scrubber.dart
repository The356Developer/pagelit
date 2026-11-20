import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';

/// Tactile horizontal page scrubber with RTL support, chapter tick markers,
/// +/-1 step buttons, throttled haptics, and a floating live preview bubble.
class PageScrubber extends StatefulWidget {
  const PageScrubber({
    super.key,
    required this.currentPage,
    required this.totalPages,
    required this.onPageSelected,
    this.onScrubChanged,
    this.labelBuilder,
    this.subtitleBuilder,
    this.chapterPages = const [],
    this.darkOverlayStyle = false,
    this.enableLiveJump = true,
  });

  /// 1-based current page number.
  final int currentPage;

  /// Total number of pages (>= 1).
  final int totalPages;

  /// Called when a page is committed (tap, +/-1 step, drag end, or pause jump).
  final ValueChanged<int> onPageSelected;

  /// Optional lightweight callback fired during scrubbing without jumping yet.
  final ValueChanged<int>? onScrubChanged;

  /// Formats the primary label in the floating preview bubble.
  final String Function(int page)? labelBuilder;

  /// Optional chapter or slide subtitle shown in the floating preview bubble.
  final String? Function(int page)? subtitleBuilder;

  /// Optional 1-based chapter start pages drawn as subtle tick markers.
  final List<int> chapterPages;

  /// Uses high-contrast light colors suitable for dark slideshow overlays.
  final bool darkOverlayStyle;

  /// When true, pausing finger movement for ~180ms during drag previews the page.
  final bool enableLiveJump;

  @override
  State<PageScrubber> createState() => _PageScrubberState();
}

class _PageScrubberState extends State<PageScrubber> {
  static const double _trackTouchHeight = 44.0;
  static const double _trackVisualHeight = 5.0;
  static const double _restingThumbSize = 16.0;
  static const double _draggingThumbSize = 22.0;
  static const double _horizontalTrackInset = 11.0;
  static const double _bubbleWidth = 220.0;
  static const double _bubbleEstimatedHeight = 58.0;

  final GlobalKey _trackKey = GlobalKey();

  bool _isDragging = false;
  int _dragPage = 1;
  int _lastHapticMs = 0;
  Timer? _liveJumpTimer;
  OverlayEntry? _previewOverlay;

  int get _safeTotal => math.max(1, widget.totalPages);

  int get _activePage =>
      (_isDragging ? _dragPage : widget.currentPage).clamp(1, _safeTotal);

  @override
  void dispose() {
    _liveJumpTimer?.cancel();
    _removePreviewOverlay();
    super.dispose();
  }

  @override
  void deactivate() {
    _liveJumpTimer?.cancel();
    _removePreviewOverlay();
    super.deactivate();
  }

  void _triggerThrottledHaptic() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastHapticMs >= 45) {
      _lastHapticMs = now;
      HapticFeedback.selectionClick();
    }
  }

  int _pageFromLocalDx(double localDx, double fullWidth, TextDirection dir) {
    if (_safeTotal <= 1 || fullWidth <= 0) return 1;
    final usableWidth = math.max(1.0, fullWidth - (_horizontalTrackInset * 2));
    final clamped = (localDx - _horizontalTrackInset).clamp(0.0, usableWidth);
    double fraction = clamped / usableWidth;
    if (dir == TextDirection.rtl) {
      fraction = 1.0 - fraction;
    }
    return (1 + (fraction * (_safeTotal - 1)).round()).clamp(1, _safeTotal);
  }

  double _fractionForPage(int page) {
    if (_safeTotal <= 1) return 0.0;
    return ((page.clamp(1, _safeTotal) - 1) / (_safeTotal - 1)).clamp(0.0, 1.0);
  }

  void _showOrUpdatePreviewOverlay() {
    if (!mounted) return;
    if (_previewOverlay != null) {
      _previewOverlay!.markNeedsBuild();
      return;
    }
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;

    _previewOverlay = OverlayEntry(
      builder: (overlayContext) {
        final trackBox =
            _trackKey.currentContext?.findRenderObject() as RenderBox?;
        if (trackBox == null || !trackBox.attached) {
          return const SizedBox.shrink();
        }
        final screenSize = MediaQuery.sizeOf(overlayContext);
        final dir = Directionality.of(context);
        final trackOrigin = trackBox.localToGlobal(Offset.zero);
        final trackWidth = trackBox.size.width;
        final usableWidth =
            math.max(1.0, trackWidth - (_horizontalTrackInset * 2));

        final frac = _fractionForPage(_dragPage);
        final visualFrac = dir == TextDirection.rtl ? 1.0 - frac : frac;
        final thumbCenterX =
            trackOrigin.dx + _horizontalTrackInset + (visualFrac * usableWidth);

        final maxLeft =
            math.max(12.0, screenSize.width - _bubbleWidth - 12.0);
        final left = (thumbCenterX - (_bubbleWidth / 2)).clamp(12.0, maxLeft);
        final top = (trackOrigin.dy - _bubbleEstimatedHeight - 10.0)
            .clamp(8.0, screenSize.height - _bubbleEstimatedHeight - 8.0);

        final scheme = Theme.of(context).colorScheme;
        final primaryText = widget.labelBuilder?.call(_dragPage) ??
            '$_dragPage / $_safeTotal';
        final subtitle = widget.subtitleBuilder?.call(_dragPage)?.trim();

        return Positioned(
          left: left,
          top: top,
          width: _bubbleWidth,
          child: IgnorePointer(
            child: Material(
              key: const ValueKey('page_scrubber_preview_bubble'),
              elevation: 8,
              borderRadius: BorderRadius.circular(14),
              color: widget.darkOverlayStyle
                  ? const Color(0xEE1F1F24)
                  : scheme.inverseSurface,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      primaryText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: widget.darkOverlayStyle
                            ? Colors.white
                            : scheme.onInverseSurface,
                      ),
                    ),
                    if (subtitle != null && subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          color: (widget.darkOverlayStyle
                                  ? Colors.white
                                  : scheme.onInverseSurface)
                              .withValues(alpha: 0.78),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );

    overlay.insert(_previewOverlay!);
  }

  void _removePreviewOverlay() {
    _previewOverlay?.remove();
    _previewOverlay = null;
  }

  void _scheduleLiveJump(int targetPage) {
    _liveJumpTimer?.cancel();
    if (!widget.enableLiveJump) return;
    _liveJumpTimer = Timer(const Duration(milliseconds: 180), () {
      if (mounted && _isDragging) {
        widget.onPageSelected(targetPage);
      }
    });
  }

  void _handleDragStart(
    DragStartDetails details,
    double trackWidth,
    TextDirection dir,
  ) {
    final page = _pageFromLocalDx(details.localPosition.dx, trackWidth, dir);
    setState(() {
      _isDragging = true;
      _dragPage = page;
    });
    _triggerThrottledHaptic();
    widget.onScrubChanged?.call(page);
    _showOrUpdatePreviewOverlay();
    _scheduleLiveJump(page);
  }

  void _handleDragUpdate(
    DragUpdateDetails details,
    double trackWidth,
    TextDirection dir,
  ) {
    final page = _pageFromLocalDx(details.localPosition.dx, trackWidth, dir);
    if (page != _dragPage) {
      setState(() => _dragPage = page);
      _triggerThrottledHaptic();
      widget.onScrubChanged?.call(page);
      _scheduleLiveJump(page);
    }
    _showOrUpdatePreviewOverlay();
  }

  void _handleDragEnd() {
    _liveJumpTimer?.cancel();
    if (!_isDragging) return;
    final committed = _dragPage.clamp(1, _safeTotal);
    _removePreviewOverlay();
    setState(() => _isDragging = false);
    widget.onPageSelected(committed);
  }

  void _handleTapUp(
    TapUpDetails details,
    double trackWidth,
    TextDirection dir,
  ) {
    _liveJumpTimer?.cancel();
    _removePreviewOverlay();
    final page = _pageFromLocalDx(details.localPosition.dx, trackWidth, dir);
    HapticFeedback.selectionClick();
    setState(() {
      _isDragging = false;
      _dragPage = page;
    });
    widget.onScrubChanged?.call(page);
    widget.onPageSelected(page);
  }

  void _stepPage(int delta) {
    final base = _activePage;
    final next = (base + delta).clamp(1, _safeTotal);
    if (next == base) return;
    HapticFeedback.selectionClick();
    setState(() => _dragPage = next);
    widget.onScrubChanged?.call(next);
    widget.onPageSelected(next);
  }

  List<int> _cappedChapterPages() {
    if (widget.chapterPages.isEmpty || _safeTotal <= 1) return const [];
    final valid = widget.chapterPages
        .where((p) => p >= 1 && p <= _safeTotal)
        .toSet()
        .toList()
      ..sort();
    if (valid.length <= 60) return valid;
    final step = (valid.length / 60).ceil();
    return [
      for (int i = 0; i < valid.length; i += step) valid[i],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final dir = Directionality.of(context);
    final isRtl = dir == TextDirection.rtl;
    final page = _activePage;

    final activeColor =
        widget.darkOverlayStyle ? Colors.white : scheme.primary;
    final inactiveTrackColor = widget.darkOverlayStyle
        ? Colors.white.withValues(alpha: 0.28)
        : scheme.surfaceContainerHighest;
    final labelColor = widget.darkOverlayStyle
        ? Colors.white.withValues(alpha: 0.9)
        : scheme.onSurfaceVariant;
    final tickColor = widget.darkOverlayStyle
        ? Colors.white.withValues(alpha: 0.55)
        : scheme.onSurfaceVariant.withValues(alpha: 0.45);

    final canPrev = page > 1;
    final canNext = page < _safeTotal;
    final thumbSize = _isDragging ? _draggingThumbSize : _restingThumbSize;
    final ticks = _cappedChapterPages();

    return LayoutBuilder(
      builder: (context, outerConstraints) {
        final showSideNumbers = outerConstraints.maxWidth >= 240;
        return Row(
          children: [
            _StepButton(
              key: const ValueKey('page_scrubber_prev'),
              tooltip: l10n.previousPage,
              icon: Transform.flip(
                flipX: isRtl,
                child: const Icon(Icons.chevron_left_rounded, size: 22),
              ),
              color: canPrev
                  ? labelColor
                  : labelColor.withValues(alpha: 0.32),
              onPressed: canPrev ? () => _stepPage(-1) : null,
            ),
            if (showSideNumbers)
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 22, maxWidth: 42),
                child: Text(
                  '$page',
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: labelColor,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            Expanded(
              child: Semantics(
                slider: true,
                value: '$page',
                label: l10n.pageNumberLabel(page, _safeTotal),
                child: LayoutBuilder(
                  key: _trackKey,
                  builder: (context, constraints) {
                    final trackWidth = constraints.maxWidth;
                    final usableWidth = math.max(
                      1.0,
                      trackWidth - (_horizontalTrackInset * 2),
                    );
                    final frac = _fractionForPage(page);
                    final visualFrac = isRtl ? 1.0 - frac : frac;
                    final thumbCenterX =
                        _horizontalTrackInset + (visualFrac * usableWidth);

                    return GestureDetector(
                      key: const ValueKey('page_scrubber_track'),
                      behavior: HitTestBehavior.opaque,
                      onHorizontalDragStart: (d) =>
                          _handleDragStart(d, trackWidth, dir),
                      onHorizontalDragUpdate: (d) =>
                          _handleDragUpdate(d, trackWidth, dir),
                      onHorizontalDragEnd: (_) => _handleDragEnd(),
                      onHorizontalDragCancel: _handleDragEnd,
                      onTapUp: (d) => _handleTapUp(d, trackWidth, dir),
                      child: SizedBox(
                        height: _trackTouchHeight,
                        width: double.infinity,
                        child: Stack(
                          clipBehavior: Clip.none,
                          alignment: Alignment.center,
                          children: [
                            // Inactive background track
                            Positioned(
                              left: _horizontalTrackInset,
                              right: _horizontalTrackInset,
                              child: Container(
                                height: _trackVisualHeight,
                                decoration: BoxDecoration(
                                  color: inactiveTrackColor,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                              ),
                            ),
                            // Active filled track
                            Positioned(
                              left: isRtl
                                  ? thumbCenterX
                                  : _horizontalTrackInset,
                              right: isRtl
                                  ? _horizontalTrackInset
                                  : (trackWidth - thumbCenterX),
                              child: Container(
                                height: _trackVisualHeight,
                                decoration: BoxDecoration(
                                  color: activeColor,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                              ),
                            ),
                            // Chapter / section tick markers
                            for (final chapterPage in ticks)
                              Positioned(
                                left: _horizontalTrackInset +
                                    ((isRtl
                                            ? 1.0 -
                                                _fractionForPage(chapterPage)
                                            : _fractionForPage(chapterPage)) *
                                        usableWidth) -
                                    1.0,
                                child: IgnorePointer(
                                  child: Container(
                                    width: 2.0,
                                    height: 9.0,
                                    decoration: BoxDecoration(
                                      color: tickColor,
                                      borderRadius: BorderRadius.circular(1),
                                    ),
                                  ),
                                ),
                              ),
                            // Interactive thumb with halo when dragging
                            Positioned(
                              left: thumbCenterX - (thumbSize / 2) - 4,
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 110),
                                curve: Curves.easeOutCubic,
                                width: thumbSize + 8,
                                height: thumbSize + 8,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _isDragging
                                      ? activeColor.withValues(alpha: 0.20)
                                      : Colors.transparent,
                                ),
                                child: Center(
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 110),
                                    curve: Curves.easeOutCubic,
                                    width: thumbSize,
                                    height: thumbSize,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: activeColor,
                                      border: Border.all(
                                        color: widget.darkOverlayStyle
                                            ? Colors.black54
                                            : scheme.surface,
                                        width: 2.0,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black
                                              .withValues(alpha: 0.25),
                                          blurRadius: _isDragging ? 8 : 4,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            if (showSideNumbers)
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 22, maxWidth: 42),
                child: Text(
                  '$_safeTotal',
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: labelColor.withValues(alpha: 0.8),
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            _StepButton(
              key: const ValueKey('page_scrubber_next'),
              tooltip: l10n.nextPage,
              icon: Transform.flip(
                flipX: isRtl,
                child: const Icon(Icons.chevron_right_rounded, size: 22),
              ),
              color: canNext
                  ? labelColor
                  : labelColor.withValues(alpha: 0.32),
              onPressed: canNext ? () => _stepPage(1) : null,
            ),
          ],
        );
      },
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  final String tooltip;
  final Widget icon;
  final Color color;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 36,
      height: 36,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 36, height: 36),
        iconSize: 22,
        color: color,
        icon: icon,
      ),
    );
  }
}
