import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/display/display_models.dart';
import '../services/display/display_service.dart';
import '../services/display/projector_window_service.dart';
import '../services/encoding_utils.dart';
import '../services/hand_tracking/hand_tracking_models.dart';
import '../services/hand_tracking/hand_tracking_prefs.dart';
import '../services/hand_tracking/hand_tracking_service.dart';
import '../services/presentation_parser.dart';
import '../services/session/document_session_controller.dart';
import '../services/session/session_models.dart';
import '../widgets/presentation_stage_canvas.dart';
import 'presentation_viewer_screen.dart' show SlideCanvasView;

/// PowerPoint-grade Dual-Screen Presenter View for Desktop:
/// - Synchronizes live slides & animations with the borderless Projector window
/// - Displays Next Animation Step / Next Slide preview
/// - High-contrast zoomable Speaker Notes reader
/// - Elapsed timer, wall clock, Black/White blackout keys, Display Swap
/// - 3-meter high-visibility Emerald Edge Glow + live 2–3m Hand Tracking camera card
class PresenterViewScreen extends StatefulWidget {
  const PresenterViewScreen({
    super.key,
    required this.deck,
    required this.filePath,
    required this.title,
    this.initialSlideIndex = 0,
    this.enableAnimations = true,
    this.autoLaunchProjector = true,
  });

  final PresentationDeck deck;
  final String filePath;
  final String title;
  final int initialSlideIndex;
  final bool enableAnimations;
  final bool autoLaunchProjector;

  /// Returns the last viewed slide index so the editor tab can sync on exit.
  static Future<int?> push(
    BuildContext context, {
    required PresentationDeck deck,
    required String filePath,
    required String title,
    int initialSlideIndex = 0,
    bool enableAnimations = true,
    bool autoLaunchProjector = true,
  }) {
    return Navigator.of(context).push<int>(
      MaterialPageRoute<int>(
        builder: (_) => PresenterViewScreen(
          deck: deck,
          filePath: filePath,
          title: title,
          initialSlideIndex: initialSlideIndex,
          enableAnimations: enableAnimations,
          autoLaunchProjector: autoLaunchProjector,
        ),
      ),
    );
  }

  @override
  State<PresenterViewScreen> createState() => _PresenterViewScreenState();
}

class _PresenterViewScreenState extends State<PresenterViewScreen> {
  late final DocumentSessionController _session;
  final ScrollController _stripScrollController = ScrollController();

  List<DisplayInfo> _displays = const [];
  int _projectorDisplayIndex = -1;
  bool _windowedProjectorTest = false;
  bool _showFilmstrip = true;
  double _leftPaneRatio = 0.58;

  String _wallClockText = '';
  Timer? _wallClockTimer;

  StreamSubscription<SessionStateSnapshot>? _snapshotSub;
  StreamSubscription<SessionCommand>? _projectorCmdSub;
  StreamSubscription<void>? _projectorClosedSub;
  StreamSubscription<List<DisplayInfo>>? _displaysChangedSub;

  List<CameraDeviceInfo> _cameras = const [];

  bool get _isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  @override
  void initState() {
    super.initState();
    HandTrackingPrefs.ensureLoaded();

    _session = DocumentSessionController.forPresentation(
      deck: widget.deck,
      filePath: widget.filePath,
      title: widget.title,
      initialSlideIndex: widget.initialSlideIndex,
      enableAnimations: widget.enableAnimations,
    );
    ActiveSessionRegistry.attach(_session);

    final ht = HandTrackingService.instance;
    if (ht.isSupported) {
      _session.registerInputSource(ht);
      ht.latestFrame.addListener(_onHandTrackingFrameChanged);
    }
    HandTrackingPrefs.showProjectorDot.addListener(_onProjectorDotPrefChanged);

    _snapshotSub = _session.snapshots.listen((snap) {
      ProjectorWindowService.instance.syncState(snap);
      _scrollFilmstripTo(snap.currentIndex);
    });

    _projectorCmdSub =
        ProjectorWindowService.instance.onProjectorCommand.listen(
      _session.dispatch,
    );
    _projectorClosedSub =
        ProjectorWindowService.instance.onProjectorClosed.listen((_) {
      if (mounted) _exitPresenterMode();
    });

    _updateWallClock();
    _wallClockTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) _updateWallClock();
    });

    _initDisplaysAndProjector();
    _displaysChangedSub =
        DisplayService.instance.onDisplaysChanged.listen(_handleDisplaysChanged);
  }

  @override
  void dispose() {
    _wallClockTimer?.cancel();
    _snapshotSub?.cancel();
    _projectorCmdSub?.cancel();
    _projectorClosedSub?.cancel();
    _displaysChangedSub?.cancel();

    final ht = HandTrackingService.instance;
    ht.latestFrame.removeListener(_onHandTrackingFrameChanged);
    HandTrackingPrefs.showProjectorDot
        .removeListener(_onProjectorDotPrefChanged);
    _session.unregisterInputSource(ht);
    if (ht.isRunning.value) {
      ht.stop();
    }

    ProjectorWindowService.instance.closeProjector();
    ActiveSessionRegistry.detach(_session);
    _session.dispose();
    _stripScrollController.dispose();
    super.dispose();
  }

  void _updateWallClock() {
    final now = DateTime.now();
    final h = now.hour % 12 == 0 ? 12 : now.hour % 12;
    final m = now.minute.toString().padLeft(2, '0');
    final ampm = now.hour >= 12 ? 'PM' : 'AM';
    setState(() => _wallClockText = '$h:$m $ampm');
  }

  void _onHandTrackingFrameChanged() {
    final frame = HandTrackingService.instance.latestFrame.value;
    _session.updateGestureFeedback(
      hudState: frame.phase.toHudState(),
      showProjectorDot: HandTrackingPrefs.showProjectorDot.value,
    );
  }

  void _onProjectorDotPrefChanged() {
    _session.updateGestureFeedback(
      showProjectorDot: HandTrackingPrefs.showProjectorDot.value,
    );
  }

  Future<void> _initDisplaysAndProjector() async {
    if (!_isDesktop) return;
    final displays = await DisplayService.instance.getDisplays();
    if (!mounted) return;
    setState(() => _displays = displays);

    if (widget.autoLaunchProjector && displays.length >= 2) {
      int secondaryIdx = displays.indexWhere((d) => !d.isPrimary);
      if (secondaryIdx == -1) secondaryIdx = 1;
      await _openProjectorOnIndex(secondaryIdx, windowed: false);
    }

    if (HandTrackingService.instance.isSupported) {
      final cams = await HandTrackingService.instance.listCameras();
      if (mounted) setState(() => _cameras = cams);
    }
  }

  Future<void> _handleDisplaysChanged(List<DisplayInfo> updated) async {
    if (!mounted) return;
    setState(() => _displays = updated);

    if (updated.length >= 2 && !ProjectorWindowService.instance.isOpen) {
      int secondaryIdx = updated.indexWhere((d) => !d.isPrimary);
      if (secondaryIdx == -1) secondaryIdx = 1;
      await _openProjectorOnIndex(secondaryIdx, windowed: false);
    } else if (updated.length < 2 &&
        ProjectorWindowService.instance.isOpen &&
        !_windowedProjectorTest) {
      await ProjectorWindowService.instance.closeProjector();
      if (mounted) setState(() => _projectorDisplayIndex = -1);
    }
  }

  Future<void> _openProjectorOnIndex(
    int displayIdx, {
    required bool windowed,
  }) async {
    if (displayIdx < 0 || displayIdx >= _displays.length) return;
    _session.updateGestureFeedback(
      showProjectorDot: HandTrackingPrefs.showProjectorDot.value,
    );
    final ok = await ProjectorWindowService.instance.openProjector(
      display: _displays[displayIdx],
      initialSnapshot: _session.value,
      windowed: windowed,
    );
    if (mounted && ok) {
      setState(() {
        _projectorDisplayIndex = displayIdx;
        _windowedProjectorTest = windowed;
      });
    }
  }

  Future<void> _swapDisplays() async {
    if (_displays.length < 2) return;
    final nextProjIdx =
        (_projectorDisplayIndex + 1) % _displays.length;
    final nextPresIdx = (nextProjIdx + 1) % _displays.length;

    if (!ProjectorWindowService.instance.isOpen) {
      await _openProjectorOnIndex(nextProjIdx, windowed: false);
      return;
    }

    final ok = await ProjectorWindowService.instance.swapOrMoveDisplays(
      projectorDisplay: _displays[nextProjIdx],
      presenterDisplay: _displays[nextPresIdx],
    );
    if (mounted && ok) {
      setState(() {
        _projectorDisplayIndex = nextProjIdx;
        _windowedProjectorTest = false;
      });
    }
  }

  Future<void> _toggleWindowedProjectorPreview() async {
    if (ProjectorWindowService.instance.isOpen) {
      await ProjectorWindowService.instance.closeProjector();
      if (mounted) {
        setState(() {
          _projectorDisplayIndex = -1;
          _windowedProjectorTest = false;
        });
      }
      return;
    }
    if (_displays.isEmpty) return;
    await _openProjectorOnIndex(0, windowed: true);
  }

  Future<void> _toggleHandTracking() async {
    final ht = HandTrackingService.instance;
    if (!ht.isSupported) return;
    if (ht.isRunning.value) {
      await ht.stop();
      _session.updateGestureFeedback(hudState: GestureHudState.off);
    } else {
      final cams = await ht.listCameras();
      if (mounted) setState(() => _cameras = cams);
      await ht.start();
    }
  }

  void _scrollFilmstripTo(int index) {
    if (!_stripScrollController.hasClients) return;
    const itemWidth = 148.0;
    final viewport = _stripScrollController.position.viewportDimension;
    final target = (index * itemWidth - viewport / 2 + itemWidth / 2).clamp(
      0.0,
      _stripScrollController.position.maxScrollExtent,
    );
    _stripScrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  void _handleEscape() {
    if (_session.value.blackoutMode != BlackoutMode.none) {
      _session.dispatch(const SetBlackoutCommand(BlackoutMode.none));
      return;
    }
    _exitPresenterMode();
  }

  void _exitPresenterMode() {
    Navigator.of(context).pop(_session.value.currentIndex);
  }

  String _formatElapsed(int ms) {
    final totalSec = ms ~/ 1000;
    final hrs = totalSec ~/ 3600;
    final mins = (totalSec % 3600) ~/ 60;
    final secs = totalSec % 60;
    final mm = mins.toString().padLeft(2, '0');
    final ss = secs.toString().padLeft(2, '0');
    if (hrs > 0) {
      return '${hrs.toString().padLeft(2, '0')}:$mm:$ss';
    }
    return '$mm:$ss';
  }

  void _openHandTrackingSettingsSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1E2128),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.front_hand_rounded,
                        color: Color(0xFF10B981),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        '2–3m Far-Field Hand Tracking Settings',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Colors.white70,
                        ),
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Stand 2–3 meters away. Hold an open palm facing the camera at chest/shoulder height (~0.2s) until the screen border glows emerald, then swipe horizontally.',
                    style: TextStyle(color: Colors.white70, fontSize: 12.5),
                  ),
                  const SizedBox(height: 16),
                  if (_cameras.isNotEmpty) ...[
                    Row(
                      children: [
                        const Text(
                          'Camera:',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: ValueListenableBuilder<String?>(
                            valueListenable:
                                HandTrackingPrefs.preferredCameraId,
                            builder: (_, preferredId, _) {
                              final selected = _cameras
                                      .where((c) => c.id == preferredId)
                                      .firstOrNull ??
                                  _cameras.first;
                              return DropdownButtonHideUnderline(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF282C35),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: DropdownButton<CameraDeviceInfo>(
                                    value: selected,
                                    dropdownColor: const Color(0xFF282C35),
                                    isExpanded: true,
                                    style: const TextStyle(color: Colors.white),
                                    items: _cameras
                                        .map(
                                          (cam) => DropdownMenuItem(
                                            value: cam,
                                            child: Text(
                                              cam.name,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        )
                                        .toList(),
                                    onChanged: (cam) async {
                                      if (cam == null) return;
                                      await HandTrackingPrefs
                                          .setPreferredCameraId(cam.id);
                                      if (HandTrackingService
                                          .instance.isRunning.value) {
                                        await HandTrackingService.instance
                                            .start(cameraIndex: cam.index);
                                      }
                                    },
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                  ValueListenableBuilder<bool>(
                    valueListenable: HandTrackingPrefs.invertSwipeDirection,
                    builder: (_, inverted, _) => SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      activeThumbColor: const Color(0xFF10B981),
                      title: const Text(
                        'Invert Swipe Direction',
                        style: TextStyle(color: Colors.white, fontSize: 14),
                      ),
                      subtitle: Text(
                        inverted
                            ? 'Swipe Left-to-Right = Next Slide'
                            : 'Swipe Right-to-Left (turn page) = Next Slide',
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 12,
                        ),
                      ),
                      value: inverted,
                      onChanged: HandTrackingPrefs.setInvertSwipe,
                    ),
                  ),
                  ValueListenableBuilder<bool>(
                    valueListenable: HandTrackingPrefs.showProjectorDot,
                    builder: (_, showDot, _) => SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      activeThumbColor: const Color(0xFF10B981),
                      title: const Text(
                        'Show Subtle Status Dot on Projector',
                        style: TextStyle(color: Colors.white, fontSize: 14),
                      ),
                      subtitle: const Text(
                        'Off by default so the audience projection stays 100% clean',
                        style: TextStyle(color: Colors.white60, fontSize: 12),
                      ),
                      value: showDot,
                      onChanged: HandTrackingPrefs.setShowProjectorDot,
                    ),
                  ),
                  ValueListenableBuilder<double>(
                    valueListenable: HandTrackingPrefs.sensitivity,
                    builder: (_, sens, _) => Row(
                      children: [
                        const Text(
                          'Swipe Sensitivity',
                          style: TextStyle(color: Colors.white, fontSize: 14),
                        ),
                        Expanded(
                          child: Slider(
                            value: sens,
                            min: 0.75,
                            max: 1.35,
                            divisions: 6,
                            activeColor: const Color(0xFF10B981),
                            label: '${(sens * 100).round()}%',
                            onChanged: HandTrackingPrefs.setSensitivity,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
            _session.dispatch(const NextStepCommand()),
        const SingleActivator(LogicalKeyboardKey.pageDown): () =>
            _session.dispatch(const NextStepCommand()),
        const SingleActivator(LogicalKeyboardKey.space): () =>
            _session.dispatch(const NextStepCommand()),
        const SingleActivator(LogicalKeyboardKey.enter): () =>
            _session.dispatch(const NextStepCommand()),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
            _session.dispatch(const PrevStepCommand()),
        const SingleActivator(LogicalKeyboardKey.pageUp): () =>
            _session.dispatch(const PrevStepCommand()),
        const SingleActivator(LogicalKeyboardKey.backspace): () =>
            _session.dispatch(const PrevStepCommand()),
        const SingleActivator(LogicalKeyboardKey.keyB): () => _session.dispatch(
              const ToggleBlackoutCommand(BlackoutMode.black),
            ),
        const SingleActivator(LogicalKeyboardKey.keyW): () => _session.dispatch(
              const ToggleBlackoutCommand(BlackoutMode.white),
            ),
        const SingleActivator(LogicalKeyboardKey.keyR): () =>
            _session.dispatch(const ReplayAnimationsCommand()),
        const SingleActivator(LogicalKeyboardKey.home): () =>
            _session.dispatch(const JumpToIndexCommand(0)),
        const SingleActivator(LogicalKeyboardKey.end): () => _session.dispatch(
              JumpToIndexCommand(widget.deck.slides.length - 1),
            ),
        const SingleActivator(LogicalKeyboardKey.escape): _handleEscape,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: const Color(0xFF121418),
          body: ValueListenableBuilder<HandTrackingFrame>(
            valueListenable: HandTrackingService.instance.latestFrame,
            builder: (context, htFrame, _) {
              return Stack(
                fit: StackFit.expand,
                children: [
                  ValueListenableBuilder<SessionStateSnapshot>(
                    valueListenable: _session,
                    builder: (context, snap, _) {
                      return Column(
                        children: [
                          _buildTopToolbar(snap, htFrame),
                          if (htFrame.phase == ClutchTrackingPhase.armed ||
                              htFrame.phase == ClutchTrackingPhase.swipeNext ||
                              htFrame.phase == ClutchTrackingPhase.swipePrev)
                            _buildThreeMeterBanner(htFrame),
                          Expanded(
                            child: _buildMainSplitWorkspace(snap, htFrame),
                          ),
                          if (_showFilmstrip) _buildBottomFilmstrip(snap),
                        ],
                      );
                    },
                  ),

                  // 3-Meter High-Visibility Perimeter Edge Glow
                  IgnorePointer(
                    child: _ThreeMeterEdgeGlowOverlay(phase: htFrame.phase),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildTopToolbar(
    SessionStateSnapshot snap,
    HandTrackingFrame htFrame,
  ) {
    final projectorOpen = ProjectorWindowService.instance.isOpen;
    final hasMultiMonitors = _displays.length >= 2;
    final htRunning = HandTrackingService.instance.isRunning.value;

    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: const BoxDecoration(
        color: Color(0xFF1A1D24),
        border: Border(
          bottom: BorderSide(color: Color(0xFF2B303B), width: 1),
        ),
      ),
      child: Row(
        children: [
          // Timer + Wall Clock
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF252932),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.timer_outlined,
                  size: 16,
                  color: Color(0xFF94A3B8),
                ),
                const SizedBox(width: 6),
                Text(
                  _formatElapsed(snap.elapsedMs),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(width: 4),
                InkWell(
                  borderRadius: BorderRadius.circular(4),
                  onTap: () =>
                      _session.dispatch(const ToggleTimerPauseCommand()),
                  child: Padding(
                    padding: const EdgeInsets.all(3),
                    child: Icon(
                      snap.isTimerRunning
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      size: 16,
                      color: Colors.white70,
                    ),
                  ),
                ),
                InkWell(
                  borderRadius: BorderRadius.circular(4),
                  onTap: () => _session.dispatch(const ResetTimerCommand()),
                  child: const Padding(
                    padding: EdgeInsets.all(3),
                    child: Icon(
                      Icons.refresh_rounded,
                      size: 15,
                      color: Colors.white60,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            _wallClockText,
            style: const TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              EncodingUtils.cleanDisplayName(widget.title),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),

          // Display / Projector Status & Swap
          if (hasMultiMonitors) ...[
            _ToolbarChipButton(
              icon: Icons.swap_horiz_rounded,
              label: projectorOpen &&
                      _projectorDisplayIndex >= 0 &&
                      _projectorDisplayIndex < _displays.length
                  ? 'Swap Screens (Screen ${_projectorDisplayIndex + 1})'
                  : 'Project on Screen 2',
              active: projectorOpen,
              activeColor: const Color(0xFF3B82F6),
              onTap: _swapDisplays,
            ),
            const SizedBox(width: 8),
          ] else if (_isDesktop && ProjectorWindowService.instance.isSupported) ...[
            _ToolbarChipButton(
              icon: Icons.picture_in_picture_alt_rounded,
              label: projectorOpen ? 'Close Test Projector' : 'Pop-Out Projector',
              active: projectorOpen,
              activeColor: const Color(0xFF3B82F6),
              onTap: _toggleWindowedProjectorPreview,
            ),
            const SizedBox(width: 8),
          ],

          // Black / White Screen Toggles
          _ToolbarChipButton(
            icon: Icons.tv_off_rounded,
            label: 'Black (B)',
            active: snap.blackoutMode == BlackoutMode.black,
            activeColor: const Color(0xFFF59E0B),
            onTap: () => _session.dispatch(
              const ToggleBlackoutCommand(BlackoutMode.black),
            ),
          ),
          const SizedBox(width: 6),
          _ToolbarChipButton(
            icon: Icons.wb_sunny_outlined,
            label: 'White (W)',
            active: snap.blackoutMode == BlackoutMode.white,
            activeColor: const Color(0xFFF59E0B),
            onTap: () => _session.dispatch(
              const ToggleBlackoutCommand(BlackoutMode.white),
            ),
          ),
          const SizedBox(width: 10),

          // 2–3m Far-Field Hand Tracking Controls
          if (HandTrackingService.instance.isSupported) ...[
            _ToolbarChipButton(
              icon: htRunning
                  ? Icons.front_hand_rounded
                  : Icons.back_hand_outlined,
              label: !htRunning
                  ? '2–3m Hand Control'
                  : htFrame.phase == ClutchTrackingPhase.armed
                      ? 'ARMED • SWIPE'
                      : 'Hand Active',
              active: htRunning,
              activeColor: htFrame.phase == ClutchTrackingPhase.armed
                  ? const Color(0xFF10B981)
                  : const Color(0xFF059669),
              onTap: _toggleHandTracking,
            ),
            IconButton(
              tooltip: 'Hand tracking settings',
              icon: const Icon(
                Icons.tune_rounded,
                size: 18,
                color: Colors.white70,
              ),
              onPressed: _openHandTrackingSettingsSheet,
            ),
            const SizedBox(width: 6),
          ],

          IconButton(
            tooltip: _showFilmstrip ? 'Hide filmstrip' : 'Show filmstrip',
            icon: Icon(
              _showFilmstrip
                  ? Icons.view_carousel_rounded
                  : Icons.view_carousel_outlined,
              size: 19,
              color: Colors.white70,
            ),
            onPressed: () => setState(() => _showFilmstrip = !_showFilmstrip),
          ),
          const SizedBox(width: 6),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            onPressed: _exitPresenterMode,
            icon: const Icon(Icons.stop_circle_outlined, size: 17),
            label: const Text('End Show'),
          ),
        ],
      ),
    );
  }

  Widget _buildThreeMeterBanner(HandTrackingFrame htFrame) {
    final (bg, text) = switch (htFrame.phase) {
      ClutchTrackingPhase.swipeNext => (
          const Color(0xFF059669),
          'NEXT SLIDE / STEP  >>',
        ),
      ClutchTrackingPhase.swipePrev => (
          const Color(0xFF0284C7),
          '<<  PREVIOUS SLIDE / STEP',
        ),
      _ => (
          const Color(0xFF10B981),
          'PALM ARMED — SWIPE HAND TO SWITCH SLIDE',
        ),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 6),
      color: bg,
      alignment: Alignment.center,
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.black,
          fontSize: 15,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildMainSplitWorkspace(
    SessionStateSnapshot snap,
    HandTrackingFrame htFrame,
  ) {
    final slides = widget.deck.slides;
    final currentSlide = slides[snap.currentIndex.clamp(0, slides.length - 1)];

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalW = constraints.maxWidth;
        final leftW = (totalW * _leftPaneRatio).clamp(360.0, totalW - 320.0);

        return Row(
          children: [
            // LEFT PANE: Live Current Slide + Step Controls
            SizedBox(
              width: leftW,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 8, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'LIVE ON PROJECTOR',
                          style: TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.9,
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (snap.blackoutMode != BlackoutMode.none)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF59E0B),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              snap.blackoutMode == BlackoutMode.white
                                  ? 'WHITE SCREEN ACTIVE'
                                  : 'BLACK SCREEN ACTIVE',
                              style: const TextStyle(
                                color: Colors.black,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        const Spacer(),
                        if (snap.totalSteps > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E293B),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color(0xFF38BDF8)
                                    .withValues(alpha: 0.5),
                              ),
                            ),
                            child: Text(
                              'Animation Step ${snap.currentStep} / ${snap.totalSteps}',
                              style: const TextStyle(
                                color: Color(0xFF38BDF8),
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFF2E3440),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.45),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: PresentationStageCanvas(
                          deck: widget.deck,
                          snapshot: snap,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildTransportBar(snap),
                  ],
                ),
              ),
            ),

            // Draggable Vertical Splitter
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragUpdate: (d) {
                setState(() {
                  _leftPaneRatio =
                      ((_leftPaneRatio * totalW + d.delta.dx) / totalW)
                          .clamp(0.38, 0.72);
                });
              },
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeColumn,
                child: Container(
                  width: 10,
                  alignment: Alignment.center,
                  child: Container(
                    width: 3,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFF333947),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
            ),

            // RIGHT PANE: Next Preview (+ Live Camera Card) + Speaker Notes
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 14, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      height: 186,
                      child: Row(
                        children: [
                          Expanded(
                            flex: 6,
                            child: _buildNextPreviewCard(snap),
                          ),
                          if (HandTrackingService.instance.isRunning.value ||
                              HandTrackingService.instance.errorMessage.value !=
                                  null) ...[
                            const SizedBox(width: 10),
                            Expanded(
                              flex: 5,
                              child: _HandTrackingCameraCard(
                                frame: htFrame,
                                onOpenSettings: _openHandTrackingSettingsSheet,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: _buildSpeakerNotesCard(currentSlide),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTransportBar(SessionStateSnapshot snap) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1D24),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2B303B)),
      ),
      child: Row(
        children: [
          FilledButton.tonalIcon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF262B36),
              foregroundColor: Colors.white,
            ),
            onPressed: snap.canStepBack
                ? () => _session.dispatch(const PrevStepCommand())
                : null,
            icon: const Icon(Icons.chevron_left_rounded, size: 22),
            label: const Text('Previous'),
          ),
          const Spacer(),
          Text(
            'Slide ${snap.currentIndex + 1} of ${snap.totalCount}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 10),
          IconButton(
            tooltip: 'Replay slide animations (R)',
            icon: const Icon(
              Icons.replay_rounded,
              size: 19,
              color: Colors.white70,
            ),
            onPressed: () =>
                _session.dispatch(const ReplayAnimationsCommand()),
          ),
          IconButton(
            tooltip: snap.isAutoPlaying ? 'Pause auto-play' : 'Auto-play slides',
            icon: Icon(
              snap.isAutoPlaying
                  ? Icons.pause_circle_filled_rounded
                  : Icons.play_circle_outline_rounded,
              size: 20,
              color: snap.isAutoPlaying
                  ? const Color(0xFF10B981)
                  : Colors.white70,
            ),
            onPressed: () =>
                _session.dispatch(const ToggleAutoPlayCommand()),
          ),
          const Spacer(),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
            ),
            onPressed: snap.canStepNext
                ? () => _session.dispatch(const NextStepCommand())
                : null,
            icon: const Icon(Icons.chevron_right_rounded, size: 22),
            label: Text(
              snap.currentStep < snap.totalSteps ? 'Next Step' : 'Next Slide',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNextPreviewCard(SessionStateSnapshot snap) {
    final slides = widget.deck.slides;
    final hasNextAnimStep = snap.currentStep < snap.totalSteps;
    final hasNextSlide = snap.currentIndex + 1 < slides.length;

    final String headerLabel;
    Widget previewBody;

    if (hasNextAnimStep) {
      headerLabel =
          'UP NEXT: ANIMATION ${snap.currentStep + 1}/${snap.totalSteps}';
      final curSlide = slides[snap.currentIndex];
      previewBody = SlideCanvasView(
        key: ValueKey(
          'next_step_${snap.currentIndex}_${snap.currentStep + 1}',
        ),
        slide: curSlide,
        aspectRatio: widget.deck.aspectRatio,
        themeColors: widget.deck.themeColors,
        enableAnimations: false,
        revealedStep: snap.currentStep + 1,
        isThumbnail: true,
      );
    } else if (hasNextSlide) {
      final nextSlide = slides[snap.currentIndex + 1];
      headerLabel = 'NEXT SLIDE (${snap.currentIndex + 2}/${slides.length})';
      previewBody = SlideCanvasView(
        key: ValueKey('next_slide_${snap.currentIndex + 1}'),
        slide: nextSlide,
        aspectRatio: widget.deck.aspectRatio,
        themeColors: widget.deck.themeColors,
        enableAnimations: false,
        isThumbnail: true,
      );
    } else {
      headerLabel = 'END OF SLIDESHOW';
      previewBody = const ColoredBox(
        color: Color(0xFF0F1115),
        child: Center(
          child: Text(
            'End of Presentation',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1D24),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2B303B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            headerLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.7,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: widget.deck.aspectRatio,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: previewBody,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpeakerNotesCard(PresentationSlide slide) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1D24),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2B303B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 8, 6),
            child: Row(
              children: [
                const Icon(
                  Icons.notes_rounded,
                  size: 16,
                  color: Color(0xFF94A3B8),
                ),
                const SizedBox(width: 8),
                const Text(
                  'SPEAKER NOTES',
                  style: TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Decrease notes font size',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(
                    Icons.text_decrease_rounded,
                    size: 17,
                    color: Colors.white70,
                  ),
                  onPressed: () => HandTrackingPrefs.setSpeakerNotesFontSize(
                    HandTrackingPrefs.speakerNotesFontSize.value - 2.0,
                  ),
                ),
                IconButton(
                  tooltip: 'Increase notes font size',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(
                    Icons.text_increase_rounded,
                    size: 17,
                    color: Colors.white70,
                  ),
                  onPressed: () => HandTrackingPrefs.setSpeakerNotesFontSize(
                    HandTrackingPrefs.speakerNotesFontSize.value + 2.0,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFF2B303B)),
          Expanded(
            child: ValueListenableBuilder<double>(
              valueListenable: HandTrackingPrefs.speakerNotesFontSize,
              builder: (context, fontSize, _) {
                if (!slide.hasSpeakerNotes) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        'No speaker notes for Slide ${slide.slideNumber}.\n\nSlide title: ${EncodingUtils.cleanDisplayName(slide.title)}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white38,
                          fontSize: (fontSize * 0.82).clamp(13.0, 22.0),
                          height: 1.5,
                        ),
                      ),
                    ),
                  );
                }

                return SelectionArea(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: slide.speakerNotes.length,
                    itemBuilder: (context, idx) {
                      final para = slide.speakerNotes[idx];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (para.isBullet)
                              Padding(
                                padding: const EdgeInsets.only(
                                  right: 8,
                                  top: 2,
                                ),
                                child: Text(
                                  para.bulletChar ?? '•',
                                  style: TextStyle(
                                    color: const Color(0xFF38BDF8),
                                    fontSize: fontSize,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            Expanded(
                              child: RichText(
                                textAlign: para.alignment,
                                text: TextSpan(
                                  children: [
                                    for (final span in para.spans)
                                      TextSpan(
                                        text: span.text,
                                        style: TextStyle(
                                          color: Colors.white.withValues(
                                            alpha: 0.93,
                                          ),
                                          fontSize: fontSize,
                                          height: 1.52,
                                          fontWeight: span.bold
                                              ? FontWeight.w700
                                              : FontWeight.w400,
                                          fontStyle: span.italic
                                              ? FontStyle.italic
                                              : FontStyle.normal,
                                          decoration: span.underline
                                              ? TextDecoration.underline
                                              : TextDecoration.none,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomFilmstrip(SessionStateSnapshot snap) {
    final slides = widget.deck.slides;
    return Container(
      height: 108,
      decoration: const BoxDecoration(
        color: Color(0xFF171920),
        border: Border(
          top: BorderSide(color: Color(0xFF2B303B), width: 1),
        ),
      ),
      child: ListView.builder(
        controller: _stripScrollController,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        itemCount: slides.length,
        itemBuilder: (context, idx) {
          final isCurrent = idx == snap.currentIndex;
          final s = slides[idx];
          return Padding(
            padding: const EdgeInsets.only(right: 10),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => _session.dispatch(JumpToIndexCommand(idx)),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                width: 138,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: isCurrent
                      ? const Color(0xFF2563EB).withValues(alpha: 0.24)
                      : const Color(0xFF222630),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isCurrent
                        ? const Color(0xFF3B82F6)
                        : const Color(0xFF323846),
                    width: isCurrent ? 2 : 1,
                  ),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(5),
                      child: FittedBox(
                        fit: BoxFit.contain,
                        child: SizedBox(
                          width: 320,
                          height: 320 / widget.deck.aspectRatio,
                          child: SlideCanvasView(
                            slide: s,
                            aspectRatio: widget.deck.aspectRatio,
                            themeColors: widget.deck.themeColors,
                            enableAnimations: false,
                            isThumbnail: true,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 5,
                      bottom: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1.5,
                        ),
                        decoration: BoxDecoration(
                          color: isCurrent
                              ? const Color(0xFF2563EB)
                              : Colors.black.withValues(alpha: 0.72),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          '${idx + 1}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    if (s.hasSpeakerNotes)
                      Positioned(
                        right: 5,
                        bottom: 4,
                        child: Container(
                          padding: const EdgeInsets.all(2.5),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.65),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Icon(
                            Icons.notes_rounded,
                            size: 11,
                            color: Colors.white70,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ToolbarChipButton extends StatelessWidget {
  const _ToolbarChipButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.activeColor,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final Color activeColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active
          ? activeColor.withValues(alpha: 0.22)
          : const Color(0xFF252932),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: active ? activeColor : const Color(0xFF343A46),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 15,
                color: active ? activeColor : Colors.white70,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: active ? Colors.white : Colors.white70,
                  fontSize: 12,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// High-contrast 6px luminous frame around Presenter View so the presenter can
/// tell at a glance from 3 meters away when the Open-Palm clutch is armed.
class _ThreeMeterEdgeGlowOverlay extends StatelessWidget {
  const _ThreeMeterEdgeGlowOverlay({required this.phase});

  final ClutchTrackingPhase phase;

  @override
  Widget build(BuildContext context) {
    final (Color? color, double width) = switch (phase) {
      ClutchTrackingPhase.armed => (const Color(0xFF10B981), 6.0),
      ClutchTrackingPhase.swipeNext => (const Color(0xFF34D399), 9.0),
      ClutchTrackingPhase.swipePrev => (const Color(0xFF38BDF8), 9.0),
      ClutchTrackingPhase.arming => (
          const Color(0xFF10B981).withValues(alpha: 0.45),
          3.0,
        ),
      _ => (null, 0.0),
    };

    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      decoration: BoxDecoration(
        border: color != null ? Border.all(color: color, width: width) : null,
        boxShadow: color != null && width >= 6.0
            ? [
                BoxShadow(
                  color: color.withValues(alpha: 0.35),
                  blurRadius: 24,
                  spreadRadius: 2,
                  blurStyle: BlurStyle.inner,
                ),
              ]
            : null,
      ),
    );
  }
}

/// Compact live camera preview + Pose/Hand skeleton card inside Presenter View.
class _HandTrackingCameraCard extends StatelessWidget {
  const _HandTrackingCameraCard({
    required this.frame,
    required this.onOpenSettings,
  });

  final HandTrackingFrame frame;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final ht = HandTrackingService.instance;
    final err = ht.errorMessage.value;

    final statusLabel = switch (frame.phase) {
      ClutchTrackingPhase.armed => 'ARMED • SWIPE',
      ClutchTrackingPhase.arming => 'HOLD PALM...',
      ClutchTrackingPhase.swipeNext => 'NEXT >>',
      ClutchTrackingPhase.swipePrev => '<< PREV',
      ClutchTrackingPhase.cooldown => 'RESETTING',
      ClutchTrackingPhase.personIdle => 'RAISE OPEN PALM',
      ClutchTrackingPhase.noPerson => 'SEARCHING (2–3m)',
      ClutchTrackingPhase.off => 'OFF',
    };

    final badgeColor = switch (frame.phase) {
      ClutchTrackingPhase.armed ||
      ClutchTrackingPhase.swipeNext =>
        const Color(0xFF10B981),
      ClutchTrackingPhase.swipePrev => const Color(0xFF38BDF8),
      ClutchTrackingPhase.arming => const Color(0xFFF59E0B),
      _ => const Color(0xFF475569),
    };

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1D24),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: frame.phase == ClutchTrackingPhase.armed
              ? const Color(0xFF10B981)
              : const Color(0xFF2B303B),
          width: frame.phase == ClutchTrackingPhase.armed ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: badgeColor,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  statusLabel,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const Spacer(),
              if (frame.estimatedDistanceMeters > 0)
                Text(
                  '~${frame.estimatedDistanceMeters.toStringAsFixed(1)}m',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              const SizedBox(width: 4),
              InkWell(
                onTap: onOpenSettings,
                child: const Icon(
                  Icons.settings_outlined,
                  size: 14,
                  color: Colors.white60,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: ColoredBox(
                color: Colors.black,
                child: err != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text(
                            err,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.redAccent,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      )
                    : ValueListenableBuilder<int?>(
                        valueListenable: ht.previewTextureId,
                        builder: (context, texId, _) {
                          return Stack(
                            fit: StackFit.expand,
                            children: [
                              if (texId != null && texId >= 0)
                                FittedBox(
                                  fit: BoxFit.cover,
                                  child: SizedBox(
                                    width: 320,
                                    height: 180,
                                    child: Texture(textureId: texId),
                                  ),
                                ),
                              CustomPaint(
                                painter: _SkeletonHudPainter(frame: frame),
                              ),
                              if (frame.fps > 0)
                                Positioned(
                                  left: 5,
                                  bottom: 4,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 5,
                                      vertical: 1,
                                    ),
                                    decoration: BoxDecoration(
                                      color:
                                          Colors.black.withValues(alpha: 0.65),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      '${frame.fps.round()} fps${frame.usingGpu ? " • GPU" : ""}',
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 9,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SkeletonHudPainter extends CustomPainter {
  const _SkeletonHudPainter({required this.frame});

  final HandTrackingFrame frame;

  @override
  void paint(Canvas canvas, Size size) {
    // Upper-body active gesture band
    final topY = frame.activeZoneTopNorm * size.height;
    final botY = frame.activeZoneBottomNorm * size.height;
    final zonePaint = Paint()
      ..color = const Color(0xFF10B981).withValues(alpha: 0.10)
      ..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTRB(0, topY, size.width, botY), zonePaint);

    final zoneLine = Paint()
      ..color = const Color(0xFF10B981).withValues(alpha: 0.40)
      ..strokeWidth = 1.0;
    canvas.drawLine(Offset(0, botY), Offset(size.width, botY), zoneLine);

    Offset scalePt(Offset norm) =>
        Offset(norm.dx * size.width, norm.dy * size.height);

    final bonePaint = Paint()
      ..color = const Color(0xFF38BDF8).withValues(alpha: 0.85)
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    void drawBone(Offset? a, Offset? b) {
      if (a != null && b != null) {
        canvas.drawLine(scalePt(a), scalePt(b), bonePaint);
      }
    }

    drawBone(frame.leftShoulderNorm, frame.rightShoulderNorm);
    drawBone(frame.leftShoulderNorm, frame.leftElbowNorm);
    drawBone(frame.leftElbowNorm, frame.leftWristNorm);
    drawBone(frame.rightShoulderNorm, frame.rightElbowNorm);
    drawBone(frame.rightElbowNorm, frame.rightWristNorm);

    // 21-point hand landmarks if present
    if (frame.handLandmarksNorm.length >= 21) {
      final handPaint = Paint()
        ..color = frame.phase == ClutchTrackingPhase.armed
            ? const Color(0xFF10B981)
            : const Color(0xFFFBBF24)
        ..strokeWidth = 1.6;
      const chains = [
        [0, 1, 2, 3, 4],
        [0, 5, 6, 7, 8],
        [0, 9, 10, 11, 12],
        [0, 13, 14, 15, 16],
        [0, 17, 18, 19, 20],
        [5, 9, 13, 17],
      ];
      for (final c in chains) {
        for (int i = 0; i + 1 < c.length; i++) {
          canvas.drawLine(
            scalePt(frame.handLandmarksNorm[c[i]]),
            scalePt(frame.handLandmarksNorm[c[i + 1]]),
            handPaint,
          );
        }
      }
    }

    // Palm target & arming ring
    if (frame.palmPositionNorm != null) {
      final p = scalePt(frame.palmPositionNorm!);
      final ringColor = frame.phase == ClutchTrackingPhase.armed
          ? const Color(0xFF10B981)
          : const Color(0xFFF59E0B);
      canvas.drawCircle(p, 5, Paint()..color = ringColor);
      if (frame.armProgress > 0.05) {
        final arcPaint = Paint()
          ..color = ringColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5;
        canvas.drawArc(
          Rect.fromCircle(center: p, radius: 12),
          -1.57,
          6.283 * frame.armProgress,
          false,
          arcPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SkeletonHudPainter oldDelegate) =>
      oldDelegate.frame != frame;
}
