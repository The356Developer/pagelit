import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../session/session_input_source.dart';
import '../session/session_models.dart';
import 'clutch_swipe_recognizer.dart';
import 'hand_tracking_models.dart';
import 'hand_tracking_prefs.dart';

/// Platform-agnostic interface for 2–3m Far-Field Hand Tracking.
abstract class HandTrackingService implements SessionInputSource {
  static final HandTrackingService instance = _createPlatformInstance();

  static HandTrackingService _createPlatformInstance() {
    if (Platform.isWindows) {
      return WindowsHandTrackingService();
    }
    return UnsupportedHandTrackingService();
  }

  bool get isSupported;
  ValueListenable<bool> get isRunning;
  ValueListenable<int?> get previewTextureId;
  ValueListenable<HandTrackingFrame> get latestFrame;
  ValueListenable<String?> get errorMessage;

  Future<List<CameraDeviceInfo>> listCameras();
  Future<bool> start({int? cameraIndex});
  Future<void> stop();
}

/// Windows native implementation backed by `pagelit/vision` (MediaFoundation
/// 1080p/720p async capture + DirectML ONNX Pose & Native-Res ROI Hand Landmarks)
/// paired with [ClutchSwipeRecognizer] for deterministic 1-Euro filtering and
/// Open-Palm Clutch + Air-Swipe recognition.
class WindowsHandTrackingService implements HandTrackingService {
  static const MethodChannel _channel = MethodChannel('pagelit/vision');
  static const EventChannel _events = EventChannel('pagelit/vision_events');

  final ValueNotifier<bool> _isRunning = ValueNotifier<bool>(false);
  final ValueNotifier<int?> _textureId = ValueNotifier<int?>(null);
  final ValueNotifier<HandTrackingFrame> _latestFrame =
      ValueNotifier<HandTrackingFrame>(
    const HandTrackingFrame(phase: ClutchTrackingPhase.off),
  );
  final ValueNotifier<String?> _errorMessage = ValueNotifier<String?>(null);

  final ClutchSwipeRecognizer _recognizer = ClutchSwipeRecognizer();
  StreamSubscription<dynamic>? _eventSub;
  SessionCommandSink? _commandSink;

  @override
  String get id => 'hand_tracking';

  @override
  String get displayName => '2–3m Hand Tracking';

  @override
  bool get isSupported => true;

  @override
  ValueListenable<bool> get isRunning => _isRunning;

  @override
  ValueListenable<int?> get previewTextureId => _textureId;

  @override
  ValueListenable<HandTrackingFrame> get latestFrame => _latestFrame;

  @override
  ValueListenable<String?> get errorMessage => _errorMessage;

  @override
  void attach(SessionCommandSink onCommand) {
    _commandSink = onCommand;
  }

  @override
  void detach() {
    _commandSink = null;
  }

  @override
  Future<List<CameraDeviceInfo>> listCameras() async {
    try {
      final raw = await _channel.invokeMethod<List<Object?>>('listCameras');
      if (raw == null) return const [];
      return raw
          .whereType<Map<Object?, Object?>>()
          .map(CameraDeviceInfo.fromMap)
          .toList();
    } on PlatformException catch (e) {
      _errorMessage.value = e.message;
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }

  @override
  Future<bool> start({int? cameraIndex}) async {
    await HandTrackingPrefs.ensureLoaded();
    _errorMessage.value = null;

    int resolvedIndex = cameraIndex ?? 0;
    if (cameraIndex == null) {
      final cams = await listCameras();
      final preferredId = HandTrackingPrefs.preferredCameraId.value;
      if (preferredId != null) {
        final match = cams.where((c) => c.id == preferredId).firstOrNull;
        if (match != null) resolvedIndex = match.index;
      }
    }

    try {
      final resp = await _channel.invokeMapMethod<String, Object?>('start', {
        'cameraIndex': resolvedIndex,
      });
      final ok = (resp?['ok'] as bool?) ?? false;
      if (!ok) {
        _errorMessage.value =
            (resp?['error'] as String?) ?? 'Could not start webcam.';
        _isRunning.value = false;
        return false;
      }

      _textureId.value = (resp?['textureId'] as num?)?.toInt();
      _recognizer.reset();
      _isRunning.value = true;
      _latestFrame.value = const HandTrackingFrame(
        phase: ClutchTrackingPhase.noPerson,
      );

      await _eventSub?.cancel();
      _eventSub = _events.receiveBroadcastStream().listen(
        _onRawVisionSample,
        onError: (Object err) {
          _errorMessage.value = '$err';
        },
      );
      return true;
    } on MissingPluginException {
      _errorMessage.value = 'Native Windows vision engine is not available.';
      _isRunning.value = false;
      return false;
    } on PlatformException catch (e) {
      _errorMessage.value = e.message ?? 'Camera startup failed.';
      _isRunning.value = false;
      return false;
    }
  }

  void _onRawVisionSample(dynamic raw) {
    if (raw is! Map<Object?, Object?>) return;
    final frame = _recognizer.processRawSample(
      raw,
      sensitivity: HandTrackingPrefs.sensitivity.value,
      invertSwipe: HandTrackingPrefs.invertSwipeDirection.value,
    );
    _latestFrame.value = frame;

    final trig = frame.triggeredGesture;
    if (trig == 'next') {
      _commandSink?.call(const NextStepCommand(sourceId: 'hand_tracking'));
    } else if (trig == 'prev') {
      _commandSink?.call(const PrevStepCommand(sourceId: 'hand_tracking'));
    }
  }

  @override
  Future<void> stop() async {
    await _eventSub?.cancel();
    _eventSub = null;
    _isRunning.value = false;
    _textureId.value = null;
    _latestFrame.value = const HandTrackingFrame(
      phase: ClutchTrackingPhase.off,
    );
    try {
      await _channel.invokeMethod<void>('stop');
    } catch (_) {}
  }

  @override
  Future<void> dispose() async {
    detach();
    await stop();
  }
}

class UnsupportedHandTrackingService implements HandTrackingService {
  final ValueNotifier<bool> _isRunning = ValueNotifier<bool>(false);
  final ValueNotifier<int?> _textureId = ValueNotifier<int?>(null);
  final ValueNotifier<HandTrackingFrame> _latestFrame =
      ValueNotifier<HandTrackingFrame>(
    const HandTrackingFrame(phase: ClutchTrackingPhase.off),
  );
  final ValueNotifier<String?> _errorMessage = ValueNotifier<String?>(null);

  @override
  String get id => 'hand_tracking_noop';

  @override
  String get displayName => 'Hand Tracking (Unsupported)';

  @override
  bool get isSupported => false;

  @override
  ValueListenable<bool> get isRunning => _isRunning;

  @override
  ValueListenable<int?> get previewTextureId => _textureId;

  @override
  ValueListenable<HandTrackingFrame> get latestFrame => _latestFrame;

  @override
  ValueListenable<String?> get errorMessage => _errorMessage;

  @override
  void attach(SessionCommandSink onCommand) {}

  @override
  void detach() {}

  @override
  Future<List<CameraDeviceInfo>> listCameras() async => const [];

  @override
  Future<bool> start({int? cameraIndex}) async => false;

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}
