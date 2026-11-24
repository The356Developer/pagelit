import 'dart:async';

import 'package:flutter/foundation.dart';

import '../presentation_parser.dart';
import 'session_input_source.dart';
import 'session_models.dart';

/// Metadata resolver for each 0-based item (slide or page) in a session.
class SessionItemMetadata {
  const SessionItemMetadata({
    this.title = '',
    this.stepCount = 0,
    this.speakerNotesPlain = '',
  });

  final String title;
  final int stepCount;
  final String speakerNotesPlain;
}

/// Shared, document-agnostic controller that synchronizes:
/// - Presenter View (PC Screen)
/// - Projector Fullscreen Window (Screen 2)
/// - Keyboard, 2–3m Hand Tracking, and future Pagelit Phone App Remote
class DocumentSessionController extends ValueNotifier<SessionStateSnapshot> {
  DocumentSessionController({
    required String sessionId,
    required SessionDocumentKind docKind,
    required String filePath,
    required String title,
    required int totalCount,
    required SessionItemMetadata Function(int index) metadataForIndex,
    int initialIndex = 0,
    bool enableAnimations = true,
    bool startTimerImmediately = true,
    this.autoPlaySlideDuration = const Duration(seconds: 4),
    this.autoPlayStepDuration = const Duration(milliseconds: 2200),
  })  : _metadataForIndex = metadataForIndex,
        super(
          _buildInitialSnapshot(
            sessionId: sessionId,
            docKind: docKind,
            filePath: filePath,
            title: title,
            totalCount: totalCount,
            initialIndex: initialIndex,
            enableAnimations: enableAnimations,
            startTimerImmediately: startTimerImmediately,
            metadataForIndex: metadataForIndex,
          ),
        ) {
    if (startTimerImmediately) {
      _startStopwatchTicker();
    }
  }

  /// Factory tailored for PowerPoint [PresentationDeck] sessions.
  factory DocumentSessionController.forPresentation({
    required PresentationDeck deck,
    required String filePath,
    required String title,
    int initialSlideIndex = 0,
    bool enableAnimations = true,
    bool startTimerImmediately = true,
  }) {
    return DocumentSessionController(
      sessionId: 'ppt_${DateTime.now().microsecondsSinceEpoch}',
      docKind: SessionDocumentKind.presentation,
      filePath: filePath,
      title: title,
      totalCount: deck.slides.length,
      initialIndex: initialSlideIndex,
      enableAnimations: enableAnimations,
      startTimerImmediately: startTimerImmediately,
      metadataForIndex: (idx) {
        if (idx < 0 || idx >= deck.slides.length) {
          return const SessionItemMetadata();
        }
        final slide = deck.slides[idx];
        return SessionItemMetadata(
          title: slide.title,
          stepCount: slide.animationClickStepCount,
          speakerNotesPlain: slide.speakerNotesPlain,
        );
      },
    );
  }

  final SessionItemMetadata Function(int index) _metadataForIndex;
  final Duration autoPlaySlideDuration;
  final Duration autoPlayStepDuration;

  final StreamController<SessionStateSnapshot> _snapshotStream =
      StreamController<SessionStateSnapshot>.broadcast();
  final StreamController<SessionCommand> _commandLogStream =
      StreamController<SessionCommand>.broadcast();
  final List<SessionInputSource> _inputs = [];

  final Stopwatch _stopwatch = Stopwatch();
  Timer? _clockTicker;
  Timer? _autoPlayTimer;
  bool _disposed = false;

  /// Broadcast stream of snapshots for Projector window IPC & Phone WebSocket sync.
  Stream<SessionStateSnapshot> get snapshots => _snapshotStream.stream;

  /// Broadcast stream of incoming commands (useful for HUD pulse animations).
  Stream<SessionCommand> get commands => _commandLogStream.stream;

  static SessionStateSnapshot _buildInitialSnapshot({
    required String sessionId,
    required SessionDocumentKind docKind,
    required String filePath,
    required String title,
    required int totalCount,
    required int initialIndex,
    required bool enableAnimations,
    required bool startTimerImmediately,
    required SessionItemMetadata Function(int index) metadataForIndex,
  }) {
    final safeTotal = totalCount < 0 ? 0 : totalCount;
    final clamped =
        safeTotal == 0 ? 0 : initialIndex.clamp(0, safeTotal - 1);
    final currentMeta = metadataForIndex(clamped);
    final nextMeta = clamped + 1 < safeTotal
        ? metadataForIndex(clamped + 1)
        : const SessionItemMetadata();

    return SessionStateSnapshot(
      sessionId: sessionId,
      docKind: docKind,
      filePath: filePath,
      title: title,
      currentIndex: clamped,
      totalCount: safeTotal,
      currentStep: 0,
      totalSteps: enableAnimations ? currentMeta.stepCount : 0,
      enableAnimations: enableAnimations,
      isTimerRunning: startTimerImmediately,
      currentItemTitle: currentMeta.title,
      nextItemTitle: nextMeta.title,
      speakerNotesPlain: currentMeta.speakerNotesPlain,
    );
  }

  void registerInputSource(SessionInputSource source) {
    if (_disposed || _inputs.contains(source)) return;
    _inputs.add(source);
    source.attach(dispatch);
  }

  void unregisterInputSource(SessionInputSource source) {
    if (_inputs.remove(source)) {
      source.detach();
    }
  }

  /// Processes any [SessionCommand] from Keyboard, Hand Tracking, UI, or Phone Remote.
  void dispatch(SessionCommand command) {
    if (_disposed) return;
    _commandLogStream.add(command);

    switch (command) {
      case NextStepCommand():
        _advanceStepOrNext(fromAutoPlay: false);
      case PrevStepCommand():
        _stepBackOrPrev();
      case NextItemCommand():
        _jumpToIndex(value.currentIndex + 1);
      case PrevItemCommand():
        _jumpToIndex(value.currentIndex - 1);
      case JumpToIndexCommand(:final index):
        _jumpToIndex(index);
      case ReplayAnimationsCommand():
        _replayCurrent();
      case ToggleBlackoutCommand(:final mode):
        final next =
            value.blackoutMode == mode ? BlackoutMode.none : mode;
        _emit(value.copyWith(blackoutMode: next, wasSlideChange: false));
      case SetBlackoutCommand(:final mode):
        if (value.blackoutMode != mode) {
          _emit(value.copyWith(blackoutMode: mode, wasSlideChange: false));
        }
      case ToggleAutoPlayCommand():
        _setAutoPlay(!value.isAutoPlaying);
      case ToggleTimerPauseCommand():
        _setTimerRunning(!value.isTimerRunning);
      case ResetTimerCommand():
        _stopwatch.reset();
        if (value.isTimerRunning) {
          _stopwatch.start();
        }
        _emit(value.copyWith(elapsedMs: 0, wasSlideChange: false));
    }
  }

  void setEnableAnimations(bool enabled) {
    if (_disposed || value.enableAnimations == enabled) return;
    final meta = _metadataForIndex(value.currentIndex);
    final nextTotalSteps = enabled ? meta.stepCount : 0;
    _emit(
      value.copyWith(
        enableAnimations: enabled,
        totalSteps: nextTotalSteps,
        currentStep: enabled ? value.currentStep.clamp(0, nextTotalSteps) : 0,
        wasSlideChange: false,
      ),
    );
  }

  void updateGestureFeedback({
    GestureHudState? hudState,
    bool? showProjectorDot,
  }) {
    if (_disposed) return;
    final nextHud = hudState ?? value.gestureHudState;
    final nextDot = showProjectorDot ?? value.showProjectorGestureDot;
    if (nextHud == value.gestureHudState &&
        nextDot == value.showProjectorGestureDot) {
      return;
    }
    _emit(
      value.copyWith(
        gestureHudState: nextHud,
        showProjectorGestureDot: nextDot,
        wasSlideChange: false,
      ),
    );
  }

  /// Updates total count dynamically (e.g., when a PDF finishes loading page count).
  void updateTotalCount(int totalCount, {int? currentIndex}) {
    if (_disposed) return;
    final safeTotal = totalCount < 0 ? 0 : totalCount;
    final idx = safeTotal == 0
        ? 0
        : (currentIndex ?? value.currentIndex).clamp(0, safeTotal - 1);
    _applySlideIndex(
      idx,
      revealedStep: 0,
      navigatingForward: idx >= value.currentIndex,
      wasSlideChange: idx != value.currentIndex,
      overrideTotalCount: safeTotal,
    );
  }

  void _advanceStepOrNext({required bool fromAutoPlay}) {
    if (value.totalCount <= 0) return;

    // Any navigation clears blackout automatically, matching PowerPoint behavior.
    final clearedBlackout = BlackoutMode.none;

    if (value.currentStep < value.totalSteps) {
      _emit(
        value.copyWith(
          currentStep: value.currentStep + 1,
          wasSlideChange: false,
          blackoutMode: clearedBlackout,
        ),
      );
      _rescheduleAutoPlay();
      return;
    }

    if (value.currentIndex < value.totalCount - 1) {
      _applySlideIndex(
        value.currentIndex + 1,
        revealedStep: 0,
        navigatingForward: true,
        wasSlideChange: true,
        blackoutMode: clearedBlackout,
      );
      _rescheduleAutoPlay();
      return;
    }

    if (fromAutoPlay && value.isAutoPlaying) {
      _applySlideIndex(
        0,
        revealedStep: 0,
        navigatingForward: true,
        wasSlideChange: true,
        blackoutMode: clearedBlackout,
      );
      _rescheduleAutoPlay();
    }
  }

  void _stepBackOrPrev() {
    if (value.totalCount <= 0) return;
    final clearedBlackout = BlackoutMode.none;

    if (value.currentStep > 0) {
      _emit(
        value.copyWith(
          currentStep: value.currentStep - 1,
          wasSlideChange: false,
          blackoutMode: clearedBlackout,
        ),
      );
      _rescheduleAutoPlay();
      return;
    }

    if (value.currentIndex > 0) {
      final prevIdx = value.currentIndex - 1;
      final prevMeta = _metadataForIndex(prevIdx);
      final prevSteps = value.enableAnimations ? prevMeta.stepCount : 0;
      _applySlideIndex(
        prevIdx,
        revealedStep: prevSteps,
        navigatingForward: false,
        wasSlideChange: true,
        blackoutMode: clearedBlackout,
      );
      _rescheduleAutoPlay();
    }
  }

  void _jumpToIndex(int targetIndex) {
    if (value.totalCount <= 0) return;
    final clamped = targetIndex.clamp(0, value.totalCount - 1);
    if (clamped == value.currentIndex && value.blackoutMode == BlackoutMode.none) {
      return;
    }
    _applySlideIndex(
      clamped,
      revealedStep: 0,
      navigatingForward: clamped >= value.currentIndex,
      wasSlideChange: clamped != value.currentIndex,
      blackoutMode: BlackoutMode.none,
    );
    _rescheduleAutoPlay();
  }

  void _replayCurrent() {
    final step =
        value.totalSteps > 0 && value.currentStep > 0 ? 1 : 0;
    _emit(
      value.copyWith(
        currentStep: step,
        replayTrigger: value.replayTrigger + 1,
        wasSlideChange: false,
        blackoutMode: BlackoutMode.none,
      ),
    );
    _rescheduleAutoPlay();
  }

  void _applySlideIndex(
    int newIndex, {
    required int revealedStep,
    required bool navigatingForward,
    required bool wasSlideChange,
    BlackoutMode? blackoutMode,
    int? overrideTotalCount,
  }) {
    final total = overrideTotalCount ?? value.totalCount;
    final currentMeta = _metadataForIndex(newIndex);
    final nextMeta = newIndex + 1 < total
        ? _metadataForIndex(newIndex + 1)
        : const SessionItemMetadata();
    final totalSteps = value.enableAnimations ? currentMeta.stepCount : 0;

    _emit(
      value.copyWith(
        currentIndex: newIndex,
        totalCount: total,
        currentStep: revealedStep.clamp(0, totalSteps),
        totalSteps: totalSteps,
        navigatingForward: navigatingForward,
        wasSlideChange: wasSlideChange,
        blackoutMode: blackoutMode ?? value.blackoutMode,
        currentItemTitle: currentMeta.title,
        nextItemTitle: nextMeta.title,
        speakerNotesPlain: currentMeta.speakerNotesPlain,
      ),
    );
  }

  void _setAutoPlay(bool enabled) {
    _autoPlayTimer?.cancel();
    _emit(value.copyWith(isAutoPlaying: enabled, wasSlideChange: false));
    if (enabled) {
      _rescheduleAutoPlay();
    }
  }

  void _rescheduleAutoPlay() {
    _autoPlayTimer?.cancel();
    if (!value.isAutoPlaying || _disposed) return;
    final hasMoreSteps = value.currentStep < value.totalSteps;
    final wait = hasMoreSteps ? autoPlayStepDuration : autoPlaySlideDuration;
    _autoPlayTimer = Timer(wait, () {
      if (!_disposed && value.isAutoPlaying) {
        _advanceStepOrNext(fromAutoPlay: true);
      }
    });
  }

  void _startStopwatchTicker() {
    _stopwatch.start();
    _clockTicker?.cancel();
    _clockTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_disposed || !value.isTimerRunning) return;
      _emit(
        value.copyWith(
          elapsedMs: _stopwatch.elapsedMilliseconds,
          wasSlideChange: false,
        ),
      );
    });
  }

  void _setTimerRunning(bool running) {
    if (running) {
      _stopwatch.start();
      if (_clockTicker == null || !_clockTicker!.isActive) {
        _startStopwatchTicker();
      }
    } else {
      _stopwatch.stop();
    }
    _emit(
      value.copyWith(
        isTimerRunning: running,
        elapsedMs: _stopwatch.elapsedMilliseconds,
        wasSlideChange: false,
      ),
    );
  }

  void _emit(SessionStateSnapshot next) {
    if (_disposed) return;
    value = next;
    if (!_snapshotStream.isClosed) {
      _snapshotStream.add(next);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _clockTicker?.cancel();
    _autoPlayTimer?.cancel();
    _stopwatch.stop();
    for (final src in List<SessionInputSource>.of(_inputs)) {
      src.detach();
    }
    _inputs.clear();
    _snapshotStream.close();
    _commandLogStream.close();
    super.dispose();
  }
}

/// Global registry exposing whichever [DocumentSessionController] is currently
/// active on Desktop (Presenter Mode or active Document Reader), enabling
/// future companion services (e.g. Pagelit Phone Wi-Fi Remote) to bind automatically.
class ActiveSessionRegistry {
  ActiveSessionRegistry._();

  static final ValueNotifier<DocumentSessionController?> activeController =
      ValueNotifier<DocumentSessionController?>(null);

  static void attach(DocumentSessionController controller) {
    activeController.value = controller;
  }

  static void detach(DocumentSessionController controller) {
    if (identical(activeController.value, controller)) {
      activeController.value = null;
    }
  }
}
