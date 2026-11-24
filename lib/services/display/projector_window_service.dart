import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../session/session_models.dart';
import 'display_models.dart';

/// Platform-agnostic controller for the secondary borderless fullscreen
/// Projector window.
abstract class ProjectorWindowService {
  static final ProjectorWindowService instance = _createPlatformInstance();

  static ProjectorWindowService _createPlatformInstance() {
    if (Platform.isWindows) {
      return WindowsProjectorWindowService();
    }
    return NoopProjectorWindowService();
  }

  bool get isSupported;

  bool get isOpen;

  /// Emits commands triggered while the Projector window has focus (e.g. `ArrowRight`, `B`).
  Stream<SessionCommand> get onProjectorCommand;

  /// Emits when the user closes/escapes the Projector window directly.
  Stream<void> get onProjectorClosed;

  /// Spawns or retargets the secondary Projector window onto [display] and pushes [initialSnapshot].
  Future<bool> openProjector({
    required DisplayInfo display,
    required SessionStateSnapshot initialSnapshot,
    bool windowed = false,
  });

  /// Pushes the latest [SessionStateSnapshot] to the Projector engine in <0.2ms.
  Future<void> syncState(SessionStateSnapshot snapshot);

  /// Moves the active Projector window to [display] (used by Swap Displays) and
  /// optionally repositions the main Presenter window onto [presenterDisplay].
  Future<bool> swapOrMoveDisplays({
    required DisplayInfo projectorDisplay,
    DisplayInfo? presenterDisplay,
  });

  /// Destroys the secondary Projector window cleanly.
  Future<void> closeProjector();
}

class WindowsProjectorWindowService implements ProjectorWindowService {
  WindowsProjectorWindowService() {
    _channel.setMethodCallHandler(_handleIncomingCall);
  }

  static const MethodChannel _channel = MethodChannel('pagelit/projector');

  final StreamController<SessionCommand> _commandController =
      StreamController<SessionCommand>.broadcast();
  final StreamController<void> _closedController =
      StreamController<void>.broadcast();

  bool _isOpen = false;

  @override
  bool get isSupported => true;

  @override
  bool get isOpen => _isOpen;

  @override
  Stream<SessionCommand> get onProjectorCommand => _commandController.stream;

  @override
  Stream<void> get onProjectorClosed => _closedController.stream;

  Future<dynamic> _handleIncomingCall(MethodCall call) async {
    switch (call.method) {
      case 'onProjectorCommand':
        final args = call.arguments;
        if (args is Map<Object?, Object?>) {
          final cmd = SessionCommand.fromMap(args);
          if (cmd != null) {
            _commandController.add(cmd);
          }
        }
      case 'onProjectorClosed':
        _isOpen = false;
        _closedController.add(null);
    }
  }

  @override
  Future<bool> openProjector({
    required DisplayInfo display,
    required SessionStateSnapshot initialSnapshot,
    bool windowed = false,
  }) async {
    try {
      final ok = await _channel.invokeMethod<bool>('openProjector', {
        'left': windowed ? display.workLeft + 80 : display.left,
        'top': windowed ? display.workTop + 60 : display.top,
        'width': windowed ? (display.workWidth * 0.62).round() : display.width,
        'height':
            windowed ? (display.workHeight * 0.62).round() : display.height,
        'windowed': windowed,
        'snapshot': initialSnapshot.toMap(),
      });
      _isOpen = ok ?? false;
      return _isOpen;
    } on PlatformException {
      _isOpen = false;
      return false;
    } on MissingPluginException {
      _isOpen = false;
      return false;
    }
  }

  @override
  Future<void> syncState(SessionStateSnapshot snapshot) async {
    if (!_isOpen) return;
    try {
      await _channel.invokeMethod<void>('syncState', snapshot.toMap());
    } catch (_) {}
  }

  @override
  Future<bool> swapOrMoveDisplays({
    required DisplayInfo projectorDisplay,
    DisplayInfo? presenterDisplay,
  }) async {
    if (!_isOpen) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('moveDisplays', {
        'projector': {
          'left': projectorDisplay.left,
          'top': projectorDisplay.top,
          'width': projectorDisplay.width,
          'height': projectorDisplay.height,
        },
        if (presenterDisplay != null)
          'presenter': {
            'left': presenterDisplay.workLeft,
            'top': presenterDisplay.workTop,
            'width': presenterDisplay.workWidth,
            'height': presenterDisplay.workHeight,
          },
      });
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> closeProjector() async {
    _isOpen = false;
    try {
      await _channel.invokeMethod<void>('closeProjector');
    } catch (_) {}
  }
}

class NoopProjectorWindowService implements ProjectorWindowService {
  @override
  bool get isSupported => false;

  @override
  bool get isOpen => false;

  @override
  Stream<SessionCommand> get onProjectorCommand => const Stream.empty();

  @override
  Stream<void> get onProjectorClosed => const Stream.empty();

  @override
  Future<bool> openProjector({
    required DisplayInfo display,
    required SessionStateSnapshot initialSnapshot,
    bool windowed = false,
  }) async =>
      false;

  @override
  Future<void> syncState(SessionStateSnapshot snapshot) async {}

  @override
  Future<bool> swapOrMoveDisplays({
    required DisplayInfo projectorDisplay,
    DisplayInfo? presenterDisplay,
  }) async =>
      false;

  @override
  Future<void> closeProjector() async {}
}
