import 'dart:math';

import 'package:flutter/material.dart';

import '../screens/presentation_viewer_screen.dart' show SlideCanvasView;
import '../services/presentation_parser.dart';
import '../services/session/session_models.dart';
import '../services/slide_image_precacher.dart';

/// Reusable high-performance presentation stage shared identically across:
/// - Secondary Borderless Projector Window (Monitor 2)
/// - Live Slide Preview inside Presenter View (Monitor 1)
/// - Single-Screen Fullscreen Slideshow
class PresentationStageCanvas extends StatefulWidget {
  const PresentationStageCanvas({
    super.key,
    required this.deck,
    required this.snapshot,
    this.showOptionalGestureDot = false,
  });

  final PresentationDeck deck;
  final SessionStateSnapshot snapshot;
  final bool showOptionalGestureDot;

  @override
  State<PresentationStageCanvas> createState() =>
      _PresentationStageCanvasState();
}

class _PresentationStageCanvasState extends State<PresentationStageCanvas> {
  int _lastPrecachedIndex = -1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _maybePrecache();
  }

  @override
  void didUpdateWidget(covariant PresentationStageCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.snapshot.currentIndex != widget.snapshot.currentIndex ||
        !identical(oldWidget.deck, widget.deck)) {
      _maybePrecache();
    }
  }

  void _maybePrecache() {
    final idx = widget.snapshot.currentIndex;
    if (idx != _lastPrecachedIndex && widget.deck.slides.isNotEmpty) {
      _lastPrecachedIndex = idx;
      SlideImagePrecacher.precacheAround(context, widget.deck, idx);
    }
  }

  Widget _buildSlideTransition(
    Widget child,
    Animation<double> animation,
    PresentationSlide targetSlide,
    int currentIndex,
    bool navigatingForward,
  ) {
    final isIncoming = child.key == ValueKey('stage_slide_$currentIndex');
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeInOutCubic,
    );

    Offset directionalOffset(Offset forwardBegin) {
      final begin = navigatingForward ? forwardBegin : -forwardBegin;
      return isIncoming ? begin : -begin;
    }

    switch (targetSlide.transitionType) {
      case SlideTransitionType.pushLeft:
        return SlideTransition(
          position: Tween<Offset>(
            begin: directionalOffset(const Offset(1.0, 0.0)),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        );
      case SlideTransitionType.pushRight:
        return SlideTransition(
          position: Tween<Offset>(
            begin: directionalOffset(const Offset(-1.0, 0.0)),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        );
      case SlideTransitionType.pushUp:
        return SlideTransition(
          position: Tween<Offset>(
            begin: directionalOffset(const Offset(0.0, 1.0)),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        );
      case SlideTransitionType.pushDown:
        return SlideTransition(
          position: Tween<Offset>(
            begin: directionalOffset(const Offset(0.0, -1.0)),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        );
      case SlideTransitionType.cover:
        if (!isIncoming) return child;
        final coverBegin = navigatingForward
            ? const Offset(1.0, 0.0)
            : const Offset(-1.0, 0.0);
        return SlideTransition(
          position: Tween<Offset>(begin: coverBegin, end: Offset.zero)
              .animate(curved),
          child: child,
        );
      case SlideTransitionType.uncover:
        if (isIncoming) return child;
        final uncoverExit = navigatingForward
            ? const Offset(-1.0, 0.0)
            : const Offset(1.0, 0.0);
        return SlideTransition(
          position: Tween<Offset>(begin: uncoverExit, end: Offset.zero)
              .animate(curved),
          child: child,
        );
      case SlideTransitionType.wipe:
        if (!isIncoming) return child;
        return AnimatedBuilder(
          animation: curved,
          child: child,
          builder: (context, builtChild) {
            return ClipRect(
              child: Align(
                alignment: navigatingForward
                    ? Alignment.centerLeft
                    : Alignment.centerRight,
                widthFactor: max(0.001, curved.value),
                child: builtChild,
              ),
            );
          },
        );
      case SlideTransitionType.split:
        if (!isIncoming) return child;
        return AnimatedBuilder(
          animation: curved,
          child: child,
          builder: (context, builtChild) {
            return ClipRect(
              child: Align(
                alignment: Alignment.center,
                widthFactor: max(0.001, curved.value),
                child: builtChild,
              ),
            );
          },
        );
      case SlideTransitionType.zoom:
        return ScaleTransition(
          scale: Tween<double>(
            begin: isIncoming ? 0.88 : 1.05,
            end: 1.0,
          ).animate(curved),
          child: FadeTransition(opacity: curved, child: child),
        );
      case SlideTransitionType.cut:
        return child;
      case SlideTransitionType.fade:
      case SlideTransitionType.none:
        return FadeTransition(opacity: animation, child: child);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.deck.slides.isEmpty) {
      return const ColoredBox(color: Colors.black);
    }

    final snap = widget.snapshot;
    final safeIdx = snap.currentIndex.clamp(0, widget.deck.slides.length - 1);
    final slide = widget.deck.slides[safeIdx];

    final transitionDuration = !snap.enableAnimations ||
            slide.transitionType == SlideTransitionType.cut
        ? Duration.zero
        : slide.transitionType == SlideTransitionType.none
            ? const Duration(milliseconds: 180)
            : Duration(milliseconds: slide.transitionDurationMs);

    final entranceDelay =
        snap.wasSlideChange && transitionDuration.inMilliseconds > 0
            ? Duration(
                milliseconds: (transitionDuration.inMilliseconds * 0.4).round(),
              )
            : Duration.zero;

    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        alignment: Alignment.center,
        children: [
          Center(
            child: AspectRatio(
              aspectRatio: widget.deck.aspectRatio,
              child: RepaintBoundary(
                child: ClipRect(
                  child: AnimatedSwitcher(
                    duration: transitionDuration,
                    layoutBuilder: (currentChild, previousChildren) {
                      if (slide.transitionType == SlideTransitionType.uncover) {
                        return Stack(
                          alignment: Alignment.center,
                          children: [
                            ?currentChild,
                            ...previousChildren,
                          ],
                        );
                      }
                      return Stack(
                        alignment: Alignment.center,
                        children: [
                          ...previousChildren,
                          ?currentChild,
                        ],
                      );
                    },
                    transitionBuilder: (child, animation) =>
                        _buildSlideTransition(
                      child,
                      animation,
                      slide,
                      safeIdx,
                      snap.navigatingForward,
                    ),
                    child: KeyedSubtree(
                      key: ValueKey('stage_slide_$safeIdx'),
                      child: SlideCanvasView(
                        slide: slide,
                        aspectRatio: widget.deck.aspectRatio,
                        themeColors: widget.deck.themeColors,
                        enableAnimations: snap.enableAnimations,
                        revealedStep: snap.currentStep,
                        replayTrigger: snap.replayTrigger,
                        entranceDelay: entranceDelay,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Audience Black / White Screen Blanking (B / W keys)
          IgnorePointer(
            ignoring: snap.blackoutMode == BlackoutMode.none,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 180),
              opacity: snap.blackoutMode == BlackoutMode.none ? 0.0 : 1.0,
              child: ColoredBox(
                color: snap.blackoutMode == BlackoutMode.white
                    ? Colors.white
                    : Colors.black,
              ),
            ),
          ),

          // Optional subtle Projector corner dot (off by default to keep Projector 100% clean)
          if (widget.showOptionalGestureDot &&
              snap.showProjectorGestureDot &&
              snap.gestureHudState != GestureHudState.off)
            Positioned(
              right: 18,
              bottom: 18,
              child: IgnorePointer(
                child: _ProjectorCornerDot(state: snap.gestureHudState),
              ),
            ),
        ],
      ),
    );
  }
}

class _ProjectorCornerDot extends StatelessWidget {
  const _ProjectorCornerDot({required this.state});

  final GestureHudState state;

  @override
  Widget build(BuildContext context) {
    final (color, size) = switch (state) {
      GestureHudState.armed => (const Color(0xFF10B981), 12.0),
      GestureHudState.swipeNext ||
      GestureHudState.swipePrev =>
        (const Color(0xFF34D399), 16.0),
      GestureHudState.detected => (const Color(0xFFF59E0B), 9.0),
      _ => (Colors.white.withValues(alpha: 0.25), 7.0),
    };

    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: state == GestureHudState.armed ||
                state == GestureHudState.swipeNext ||
                state == GestureHudState.swipePrev
            ? [
                BoxShadow(
                  color: color.withValues(alpha: 0.7),
                  blurRadius: 12,
                  spreadRadius: 2,
                ),
              ]
            : null,
      ),
    );
  }
}
