import 'dart:ui';

import '../session/session_models.dart';

/// Webcam device descriptor returned by the native MediaFoundation backend.
class CameraDeviceInfo {
  const CameraDeviceInfo({
    required this.index,
    required this.id,
    required this.name,
  });

  final int index;
  final String id;
  final String name;

  factory CameraDeviceInfo.fromMap(Map<Object?, Object?> map) {
    return CameraDeviceInfo(
      index: (map['index'] as num?)?.toInt() ?? 0,
      id: (map['id'] as String?) ?? 'cam_0',
      name: (map['name'] as String?) ?? 'Camera',
    );
  }
}

/// Phase of the far-field (2–3m) Open-Palm Clutch + Air-Swipe recognizer.
enum ClutchTrackingPhase {
  off,
  noPerson,
  personIdle,
  arming,
  armed,
  swipeNext,
  swipePrev,
  cooldown;

  static ClutchTrackingPhase fromName(String? raw) {
    return ClutchTrackingPhase.values.firstWhere(
      (e) => e.name == raw,
      orElse: () => ClutchTrackingPhase.noPerson,
    );
  }

  GestureHudState toHudState() => switch (this) {
        ClutchTrackingPhase.off => GestureHudState.off,
        ClutchTrackingPhase.noPerson => GestureHudState.searching,
        ClutchTrackingPhase.personIdle ||
        ClutchTrackingPhase.arming =>
          GestureHudState.detected,
        ClutchTrackingPhase.armed => GestureHudState.armed,
        ClutchTrackingPhase.swipeNext => GestureHudState.swipeNext,
        ClutchTrackingPhase.swipePrev => GestureHudState.swipePrev,
        ClutchTrackingPhase.cooldown => GestureHudState.cooldown,
      };
}

/// Normalized telemetry & skeleton frame streamed from the native C++ vision
/// worker (or Dart gesture state machine) at ~30 FPS.
class HandTrackingFrame {
  const HandTrackingFrame({
    required this.phase,
    this.armProgress = 0.0,
    this.swipeDisplacementNorm = 0.0,
    this.estimatedDistanceMeters = 0.0,
    this.fps = 0.0,
    this.usingGpu = false,
    this.activeZoneTopNorm = 0.12,
    this.activeZoneBottomNorm = 0.72,
    this.palmPositionNorm,
    this.leftShoulderNorm,
    this.rightShoulderNorm,
    this.leftElbowNorm,
    this.rightElbowNorm,
    this.leftWristNorm,
    this.rightWristNorm,
    this.handLandmarksNorm = const [],
    this.extendedFingers = 0,
    this.triggeredGesture,
    this.statusMessage,
  });

  final ClutchTrackingPhase phase;

  /// `0.0..1.0` progress toward the 200ms Open-Palm clutch lock-on.
  final double armProgress;

  /// Torso-normalized horizontal displacement while armed (`-1.0..1.0`).
  final double swipeDisplacementNorm;

  /// Approximate presenter distance from camera in meters (derived from shoulder/torso span).
  final double estimatedDistanceMeters;

  final double fps;
  final bool usingGpu;

  /// Normalized Y bounds (`0..1` in mirrored camera view) of the upper-body gesture zone.
  final double activeZoneTopNorm;
  final double activeZoneBottomNorm;

  /// Mirrored normalized coordinates (`0..1`, `0..1`) for camera preview skeleton overlay.
  final Offset? palmPositionNorm;
  final Offset? leftShoulderNorm;
  final Offset? rightShoulderNorm;
  final Offset? leftElbowNorm;
  final Offset? rightElbowNorm;
  final Offset? leftWristNorm;
  final Offset? rightWristNorm;

  /// Up to 21 normalized hand landmarks in mirrored camera space.
  final List<Offset> handLandmarksNorm;

  final int extendedFingers;

  /// `'next'` or `'prev'` on the exact frame a swipe triggers, else `null`.
  final String? triggeredGesture;

  final String? statusMessage;

  static Offset? _decodePoint(Object? raw) {
    if (raw is List && raw.length >= 2) {
      final x = (raw[0] as num?)?.toDouble();
      final y = (raw[1] as num?)?.toDouble();
      if (x != null && y != null) return Offset(x, y);
    }
    return null;
  }

  factory HandTrackingFrame.fromMap(Map<Object?, Object?> map) {
    final landmarksRaw = map['handLandmarks'] as List?;
    final landmarks = <Offset>[];
    if (landmarksRaw != null) {
      for (int i = 0; i + 1 < landmarksRaw.length; i += 2) {
        final x = (landmarksRaw[i] as num?)?.toDouble();
        final y = (landmarksRaw[i + 1] as num?)?.toDouble();
        if (x != null && y != null) {
          landmarks.add(Offset(x, y));
        }
      }
    }

    return HandTrackingFrame(
      phase: ClutchTrackingPhase.fromName(map['phase'] as String?),
      armProgress: (map['armProgress'] as num?)?.toDouble() ?? 0.0,
      swipeDisplacementNorm:
          (map['swipeDisplacementNorm'] as num?)?.toDouble() ?? 0.0,
      estimatedDistanceMeters:
          (map['estimatedDistanceMeters'] as num?)?.toDouble() ?? 0.0,
      fps: (map['fps'] as num?)?.toDouble() ?? 0.0,
      usingGpu: (map['usingGpu'] as bool?) ?? false,
      activeZoneTopNorm: (map['activeZoneTop'] as num?)?.toDouble() ?? 0.10,
      activeZoneBottomNorm:
          (map['activeZoneBottom'] as num?)?.toDouble() ?? 0.72,
      palmPositionNorm: _decodePoint(map['palm']),
      leftShoulderNorm: _decodePoint(map['lShoulder']),
      rightShoulderNorm: _decodePoint(map['rShoulder']),
      leftElbowNorm: _decodePoint(map['lElbow']),
      rightElbowNorm: _decodePoint(map['rElbow']),
      leftWristNorm: _decodePoint(map['lWrist']),
      rightWristNorm: _decodePoint(map['rWrist']),
      handLandmarksNorm: landmarks,
      extendedFingers: (map['extendedFingers'] as num?)?.toInt() ?? 0,
      triggeredGesture: map['triggeredGesture'] as String?,
      statusMessage: map['statusMessage'] as String?,
    );
  }
}
