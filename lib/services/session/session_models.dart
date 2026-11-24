import 'dart:convert';

/// Kind of document controlled by a [DocumentSessionController].
enum SessionDocumentKind {
  presentation,
  pdf,
  word,
  excel;

  static SessionDocumentKind fromName(String? raw) {
    return SessionDocumentKind.values.firstWhere(
      (e) => e.name == raw,
      orElse: () => SessionDocumentKind.presentation,
    );
  }
}

/// Audience screen blanking mode (PowerPoint `B` / `W` shortcuts).
enum BlackoutMode {
  none,
  black,
  white;

  static BlackoutMode fromName(String? raw) {
    return BlackoutMode.values.firstWhere(
      (e) => e.name == raw,
      orElse: () => BlackoutMode.none,
    );
  }
}

/// Visual state of far-field gesture tracking for HUD/Projector indicator.
enum GestureHudState {
  off,
  searching,
  detected,
  armed,
  swipeNext,
  swipePrev,
  cooldown;

  static GestureHudState fromName(String? raw) {
    return GestureHudState.values.firstWhere(
      (e) => e.name == raw,
      orElse: () => GestureHudState.off,
    );
  }
}

/// Serializable command dispatched by Keyboard, 2–3m Hand Tracking,
/// Presenter View controls, or a future Pagelit Mobile Remote over LAN.
sealed class SessionCommand {
  const SessionCommand({this.sourceId = 'ui'});

  final String sourceId;

  String get type;

  Map<String, Object?> toMap() => {
        'type': type,
        'sourceId': sourceId,
      };

  String toJson() => jsonEncode(toMap());

  static SessionCommand? fromMap(Map<Object?, Object?> map) {
    final type = map['type'] as String?;
    final sourceId = (map['sourceId'] as String?) ?? 'remote';
    return switch (type) {
      'nextStep' => NextStepCommand(sourceId: sourceId),
      'prevStep' => PrevStepCommand(sourceId: sourceId),
      'nextItem' => NextItemCommand(sourceId: sourceId),
      'prevItem' => PrevItemCommand(sourceId: sourceId),
      'jumpToIndex' => JumpToIndexCommand(
          (map['index'] as num?)?.toInt() ?? 0,
          sourceId: sourceId,
        ),
      'replayAnimations' => ReplayAnimationsCommand(sourceId: sourceId),
      'toggleBlackout' => ToggleBlackoutCommand(
          BlackoutMode.fromName(map['mode'] as String?),
          sourceId: sourceId,
        ),
      'setBlackout' => SetBlackoutCommand(
          BlackoutMode.fromName(map['mode'] as String?),
          sourceId: sourceId,
        ),
      'toggleAutoPlay' => ToggleAutoPlayCommand(sourceId: sourceId),
      'toggleTimerPause' => ToggleTimerPauseCommand(sourceId: sourceId),
      'resetTimer' => ResetTimerCommand(sourceId: sourceId),
      _ => null,
    };
  }

  static SessionCommand? fromJson(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<Object?, Object?>) {
        return fromMap(decoded);
      }
    } catch (_) {}
    return null;
  }
}

/// Advances the next animation click step on the current slide, or moves to the next slide/page.
final class NextStepCommand extends SessionCommand {
  const NextStepCommand({super.sourceId});

  @override
  String get type => 'nextStep';
}

/// Steps back one animation step on the current slide, or moves to the previous slide/page.
final class PrevStepCommand extends SessionCommand {
  const PrevStepCommand({super.sourceId});

  @override
  String get type => 'prevStep';
}

/// Skips remaining steps on the current slide and jumps to the next slide/page.
final class NextItemCommand extends SessionCommand {
  const NextItemCommand({super.sourceId});

  @override
  String get type => 'nextItem';
}

/// Skips straight to the start of the previous slide/page.
final class PrevItemCommand extends SessionCommand {
  const PrevItemCommand({super.sourceId});

  @override
  String get type => 'prevItem';
}

/// Jumps directly to [index] (0-based slide or page index).
final class JumpToIndexCommand extends SessionCommand {
  const JumpToIndexCommand(this.index, {super.sourceId});

  final int index;

  @override
  String get type => 'jumpToIndex';

  @override
  Map<String, Object?> toMap() => {
        ...super.toMap(),
        'index': index,
      };
}

/// Replays entrance animations on the current slide.
final class ReplayAnimationsCommand extends SessionCommand {
  const ReplayAnimationsCommand({super.sourceId});

  @override
  String get type => 'replayAnimations';
}

/// Toggles [mode] (if already in [mode], returns to [BlackoutMode.none]).
final class ToggleBlackoutCommand extends SessionCommand {
  const ToggleBlackoutCommand(this.mode, {super.sourceId});

  final BlackoutMode mode;

  @override
  String get type => 'toggleBlackout';

  @override
  Map<String, Object?> toMap() => {
        ...super.toMap(),
        'mode': mode.name,
      };
}

/// Explicitly sets audience blackout mode.
final class SetBlackoutCommand extends SessionCommand {
  const SetBlackoutCommand(this.mode, {super.sourceId});

  final BlackoutMode mode;

  @override
  String get type => 'setBlackout';

  @override
  Map<String, Object?> toMap() => {
        ...super.toMap(),
        'mode': mode.name,
      };
}

/// Toggles automatic slide progression.
final class ToggleAutoPlayCommand extends SessionCommand {
  const ToggleAutoPlayCommand({super.sourceId});

  @override
  String get type => 'toggleAutoPlay';
}

/// Pauses or resumes the presenter elapsed stopwatch.
final class ToggleTimerPauseCommand extends SessionCommand {
  const ToggleTimerPauseCommand({super.sourceId});

  @override
  String get type => 'toggleTimerPause';
}

/// Resets the presenter elapsed stopwatch to 00:00.
final class ResetTimerCommand extends SessionCommand {
  const ResetTimerCommand({super.sourceId});

  @override
  String get type => 'resetTimer';
}

/// Immutable, wire-serializable state snapshot shared across:
/// - Presenter View (Primary Window)
/// - Projector Engine (Secondary Fullscreen Window via C++ BinaryMessenger)
/// - Future Pagelit Mobile Companion App (via JSON WebSocket)
class SessionStateSnapshot {
  const SessionStateSnapshot({
    required this.sessionId,
    required this.docKind,
    required this.filePath,
    required this.title,
    required this.currentIndex,
    required this.totalCount,
    this.currentStep = 0,
    this.totalSteps = 0,
    this.replayTrigger = 0,
    this.navigatingForward = true,
    this.wasSlideChange = false,
    this.enableAnimations = true,
    this.blackoutMode = BlackoutMode.none,
    this.isAutoPlaying = false,
    this.elapsedMs = 0,
    this.isTimerRunning = true,
    this.currentItemTitle = '',
    this.nextItemTitle = '',
    this.speakerNotesPlain = '',
    this.showProjectorGestureDot = false,
    this.gestureHudState = GestureHudState.off,
  });

  final String sessionId;
  final SessionDocumentKind docKind;
  final String filePath;
  final String title;

  /// 0-based index of the active slide or page.
  final int currentIndex;
  final int totalCount;

  /// Current revealed click-step (`0` = initial slide entry, `1..totalSteps` = click steps).
  final int currentStep;
  final int totalSteps;

  final int replayTrigger;
  final bool navigatingForward;
  final bool wasSlideChange;
  final bool enableAnimations;
  final BlackoutMode blackoutMode;
  final bool isAutoPlaying;

  /// Elapsed presentation time in milliseconds.
  final int elapsedMs;
  final bool isTimerRunning;

  /// Metadata useful for compact remote clients (e.g. Pagelit Phone Remote).
  final String currentItemTitle;
  final String nextItemTitle;
  final String speakerNotesPlain;

  /// Optional subtle gesture indicator on Projector screen (off by default).
  final bool showProjectorGestureDot;
  final GestureHudState gestureHudState;

  bool get canStepBack => currentIndex > 0 || currentStep > 0;
  bool get canStepNext =>
      currentIndex < totalCount - 1 || currentStep < totalSteps;
  bool get isAtEnd => !canStepNext;

  SessionStateSnapshot copyWith({
    String? sessionId,
    SessionDocumentKind? docKind,
    String? filePath,
    String? title,
    int? currentIndex,
    int? totalCount,
    int? currentStep,
    int? totalSteps,
    int? replayTrigger,
    bool? navigatingForward,
    bool? wasSlideChange,
    bool? enableAnimations,
    BlackoutMode? blackoutMode,
    bool? isAutoPlaying,
    int? elapsedMs,
    bool? isTimerRunning,
    String? currentItemTitle,
    String? nextItemTitle,
    String? speakerNotesPlain,
    bool? showProjectorGestureDot,
    GestureHudState? gestureHudState,
  }) {
    return SessionStateSnapshot(
      sessionId: sessionId ?? this.sessionId,
      docKind: docKind ?? this.docKind,
      filePath: filePath ?? this.filePath,
      title: title ?? this.title,
      currentIndex: currentIndex ?? this.currentIndex,
      totalCount: totalCount ?? this.totalCount,
      currentStep: currentStep ?? this.currentStep,
      totalSteps: totalSteps ?? this.totalSteps,
      replayTrigger: replayTrigger ?? this.replayTrigger,
      navigatingForward: navigatingForward ?? this.navigatingForward,
      wasSlideChange: wasSlideChange ?? this.wasSlideChange,
      enableAnimations: enableAnimations ?? this.enableAnimations,
      blackoutMode: blackoutMode ?? this.blackoutMode,
      isAutoPlaying: isAutoPlaying ?? this.isAutoPlaying,
      elapsedMs: elapsedMs ?? this.elapsedMs,
      isTimerRunning: isTimerRunning ?? this.isTimerRunning,
      currentItemTitle: currentItemTitle ?? this.currentItemTitle,
      nextItemTitle: nextItemTitle ?? this.nextItemTitle,
      speakerNotesPlain: speakerNotesPlain ?? this.speakerNotesPlain,
      showProjectorGestureDot:
          showProjectorGestureDot ?? this.showProjectorGestureDot,
      gestureHudState: gestureHudState ?? this.gestureHudState,
    );
  }

  Map<String, Object?> toMap() => {
        'sessionId': sessionId,
        'docKind': docKind.name,
        'filePath': filePath,
        'title': title,
        'currentIndex': currentIndex,
        'totalCount': totalCount,
        'currentStep': currentStep,
        'totalSteps': totalSteps,
        'replayTrigger': replayTrigger,
        'navigatingForward': navigatingForward,
        'wasSlideChange': wasSlideChange,
        'enableAnimations': enableAnimations,
        'blackoutMode': blackoutMode.name,
        'isAutoPlaying': isAutoPlaying,
        'elapsedMs': elapsedMs,
        'isTimerRunning': isTimerRunning,
        'currentItemTitle': currentItemTitle,
        'nextItemTitle': nextItemTitle,
        'speakerNotesPlain': speakerNotesPlain,
        'showProjectorGestureDot': showProjectorGestureDot,
        'gestureHudState': gestureHudState.name,
      };

  String toJson() => jsonEncode(toMap());

  factory SessionStateSnapshot.fromMap(Map<Object?, Object?> map) {
    return SessionStateSnapshot(
      sessionId: (map['sessionId'] as String?) ?? '',
      docKind: SessionDocumentKind.fromName(map['docKind'] as String?),
      filePath: (map['filePath'] as String?) ?? '',
      title: (map['title'] as String?) ?? '',
      currentIndex: (map['currentIndex'] as num?)?.toInt() ?? 0,
      totalCount: (map['totalCount'] as num?)?.toInt() ?? 0,
      currentStep: (map['currentStep'] as num?)?.toInt() ?? 0,
      totalSteps: (map['totalSteps'] as num?)?.toInt() ?? 0,
      replayTrigger: (map['replayTrigger'] as num?)?.toInt() ?? 0,
      navigatingForward: (map['navigatingForward'] as bool?) ?? true,
      wasSlideChange: (map['wasSlideChange'] as bool?) ?? false,
      enableAnimations: (map['enableAnimations'] as bool?) ?? true,
      blackoutMode: BlackoutMode.fromName(map['blackoutMode'] as String?),
      isAutoPlaying: (map['isAutoPlaying'] as bool?) ?? false,
      elapsedMs: (map['elapsedMs'] as num?)?.toInt() ?? 0,
      isTimerRunning: (map['isTimerRunning'] as bool?) ?? true,
      currentItemTitle: (map['currentItemTitle'] as String?) ?? '',
      nextItemTitle: (map['nextItemTitle'] as String?) ?? '',
      speakerNotesPlain: (map['speakerNotesPlain'] as String?) ?? '',
      showProjectorGestureDot:
          (map['showProjectorGestureDot'] as bool?) ?? false,
      gestureHudState:
          GestureHudState.fromName(map['gestureHudState'] as String?),
    );
  }

  factory SessionStateSnapshot.fromJson(String raw) {
    final decoded = jsonDecode(raw) as Map<Object?, Object?>;
    return SessionStateSnapshot.fromMap(decoded);
  }
}
