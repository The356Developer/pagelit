import 'dart:math';
import 'dart:ui';

import 'hand_tracking_models.dart';

/// 1-Euro adaptive low-pass filter (Casiez et al., CHI 2012) for jitter-free
/// 2–3m landmark smoothing with near-zero lag during rapid swipes.
class OneEuroFilter1D {
  OneEuroFilter1D({
    this.minCutoff = 1.4,
    this.beta = 0.045,
    this.dCutoff = 1.0,
  });

  final double minCutoff;
  final double beta;
  final double dCutoff;

  double? _prevX;
  double _prevDx = 0.0;

  void reset() {
    _prevX = null;
    _prevDx = 0.0;
  }

  double _alpha(double cutoff, double dt) {
    final tau = 1.0 / (2.0 * pi * cutoff);
    return 1.0 / (1.0 + tau / max(1e-4, dt));
  }

  double filter(double x, double dt) {
    if (_prevX == null || dt <= 0.0) {
      _prevX = x;
      _prevDx = 0.0;
      return x;
    }
    final rawDx = (x - _prevX!) / dt;
    final aD = _alpha(dCutoff, dt);
    final edx = aD * rawDx + (1.0 - aD) * _prevDx;
    _prevDx = edx;

    final cutoff = minCutoff + beta * edx.abs();
    final aX = _alpha(cutoff, dt);
    final hatX = aX * x + (1.0 - aX) * _prevX!;
    _prevX = hatX;
    return hatX;
  }
}

/// Deterministic, torso-normalized far-field (2–3m) gesture recognizer:
/// - Gates on Upper-Body Active Zone so resting/talking hands don't arm
/// - Requires steady Open-Palm facing camera (~180ms) to engage clutch
/// - Latches clutch against motion blur during fast horizontal air swipes
/// - Rejects return strokes during post-swipe cooldown
class ClutchSwipeRecognizer {
  static const int _armDurationMs = 180;
  static const int _armedTimeoutMs = 2600;
  static const int _motionBlurGraceMs = 450;
  static const int _cooldownMs = 680;
  static const int _flashHoldMs = 240;

  final OneEuroFilter1D _filterX = OneEuroFilter1D();
  final OneEuroFilter1D _filterY = OneEuroFilter1D();

  ClutchTrackingPhase _state = ClutchTrackingPhase.noPerson;
  int? _lastTimestampMs;
  double _armAccumMs = 0.0;
  int _armedSinceMs = 0;
  int _lastOpenPalmSeenMs = 0;
  int _cooldownUntilMs = 0;
  int _flashUntilMs = 0;
  ClutchTrackingPhase _flashPhase = ClutchTrackingPhase.swipeNext;

  double _anchorX = 0.5;
  double? _prevFilteredX;
  int _lastSwipeSign = 0;

  void reset() {
    _filterX.reset();
    _filterY.reset();
    _state = ClutchTrackingPhase.noPerson;
    _lastTimestampMs = null;
    _armAccumMs = 0.0;
    _armedSinceMs = 0;
    _lastOpenPalmSeenMs = 0;
    _cooldownUntilMs = 0;
    _flashUntilMs = 0;
    _prevFilteredX = null;
    _lastSwipeSign = 0;
  }

  static Offset? _pt(Object? raw) {
    if (raw is List && raw.length >= 2) {
      final x = (raw[0] as num?)?.toDouble();
      final y = (raw[1] as num?)?.toDouble();
      if (x != null && y != null) return Offset(x, y);
    }
    return null;
  }

  /// Evaluates 21 normalized hand landmarks to count extended fingers and
  /// verify palm faces toward/away from camera rather than edge-on.
  static ({int extendedCount, bool isOpenPalm}) evaluateHandOpenPalm(
    List<Offset> lm,
  ) {
    if (lm.length < 21) {
      return (extendedCount: 0, isOpenPalm: false);
    }
    final wrist = lm[0];
    int extended = 0;

    // Thumb: tip (4) vs IP (3) and pinky MCP (17)
    final thumbSpan = (lm[4] - lm[17]).distance;
    final thumbBaseSpan = (lm[2] - lm[17]).distance;
    if (thumbBaseSpan > 1e-4 && thumbSpan > 1.14 * thumbBaseSpan) {
      extended++;
    }

    // Index (5..8), Middle (9..12), Ring (13..16), Pinky (17..20)
    const fingerRoots = [5, 9, 13, 17];
    for (final mcpIdx in fingerRoots) {
      final mcp = lm[mcpIdx];
      final pip = lm[mcpIdx + 1];
      final tip = lm[mcpIdx + 3];
      final dTip = (tip - wrist).distance;
      final dPip = (pip - wrist).distance;
      final dMcp = (mcp - wrist).distance;
      if (dMcp > 1e-4 && dTip > 1.22 * dPip && dTip > 1.42 * dMcp) {
        extended++;
      }
    }

    final palmWidth = (lm[5] - lm[17]).distance;
    final palmLen = max(1e-4, (lm[9] - wrist).distance);
    final palmAspect = palmWidth / palmLen;

    final isOpen = extended >= 4 && palmAspect >= 0.42;
    return (extendedCount: extended, isOpenPalm: isOpen);
  }

  HandTrackingFrame processRawSample(
    Map<Object?, Object?> raw, {
    double sensitivity = 1.0,
    bool invertSwipe = false,
  }) {
    final nowMs = (raw['timestampMs'] as num?)?.toInt() ??
        DateTime.now().millisecondsSinceEpoch;
    final dtSec = _lastTimestampMs == null
        ? (1.0 / 30.0)
        : ((nowMs - _lastTimestampMs!).clamp(5, 200) / 1000.0);
    _lastTimestampMs = nowMs;

    final personDetected = (raw['personDetected'] as bool?) ?? false;
    final fps = (raw['fps'] as num?)?.toDouble() ?? 0.0;
    final usingGpu = (raw['usingGpu'] as bool?) ?? false;
    final statusMsg = raw['statusMessage'] as String?;

    final lSh = _pt(raw['lShoulder']);
    final rSh = _pt(raw['rShoulder']);
    final lEl = _pt(raw['lElbow']);
    final rEl = _pt(raw['rElbow']);
    final lWr = _pt(raw['lWrist']);
    final rWr = _pt(raw['rWrist']);
    final rawPalm = _pt(raw['palm']);

    final landmarks = <Offset>[];
    final lmRaw = raw['handLandmarks'] as List?;
    if (lmRaw != null) {
      for (int i = 0; i + 1 < lmRaw.length; i += 2) {
        final x = (lmRaw[i] as num?)?.toDouble();
        final y = (lmRaw[i + 1] as num?)?.toDouble();
        if (x != null && y != null) landmarks.add(Offset(x, y));
      }
    }

    if (!personDetected || (lSh == null && rSh == null)) {
      _armAccumMs = 0.0;
      _prevFilteredX = null;
      _state = ClutchTrackingPhase.noPerson;
      return HandTrackingFrame(
        phase: ClutchTrackingPhase.noPerson,
        fps: fps,
        usingGpu: usingGpu,
        statusMessage: statusMsg ?? 'Step into camera view (2–3m)',
      );
    }

    // Compute torso scale & estimated distance in meters
    final shLeft = lSh ?? rSh!;
    final shRight = rSh ?? lSh!;
    final shoulderSpan = (shLeft - shRight).distance;
    final rawTorsoScale = (raw['torsoScale'] as num?)?.toDouble() ??
        max(0.12, shoulderSpan * 1.65);
    final torsoScale = rawTorsoScale.clamp(0.08, 0.65);
    final estMeters = shoulderSpan > 0.03
        ? (0.31 / shoulderSpan).clamp(0.6, 5.0)
        : (0.48 / torsoScale).clamp(0.6, 5.0);

    final shoulderMidY = 0.5 * (shLeft.dy + shRight.dy);
    final activeTop = (shoulderMidY - 0.85 * torsoScale).clamp(0.02, 0.55);
    final activeBottom = (shoulderMidY + 0.82 * torsoScale).clamp(0.35, 0.90);

    // Choose active raised hand (prefer palm from Stage 2, else highest raised wrist)
    Offset? candidateHand = rawPalm;
    if (candidateHand == null) {
      if (lWr != null && rWr != null) {
        candidateHand = lWr.dy <= rWr.dy ? lWr : rWr;
      } else {
        candidateHand = lWr ?? rWr;
      }
    }

    final handEval = evaluateHandOpenPalm(landmarks);
    final nativeOpenScore =
        (raw['openPalmScore'] as num?)?.toDouble() ?? 0.0;
    final isOpenPalm = handEval.isOpenPalm || nativeOpenScore >= 0.65;
    final extendedFingers = handEval.extendedCount > 0
        ? handEval.extendedCount
        : (isOpenPalm ? 5 : 0);

    if (isOpenPalm) {
      _lastOpenPalmSeenMs = nowMs;
    }

    Offset? filteredPalm;
    double vxNorm = 0.0;
    if (candidateHand != null) {
      final fx = _filterX.filter(candidateHand.dx, dtSec);
      final fy = _filterY.filter(candidateHand.dy, dtSec);
      filteredPalm = Offset(fx, fy);
      if (_prevFilteredX != null) {
        vxNorm = (fx - _prevFilteredX!) / (torsoScale * dtSec);
      }
      _prevFilteredX = fx;
    } else {
      _filterX.reset();
      _filterY.reset();
      _prevFilteredX = null;
    }

    final inActiveZone = filteredPalm != null &&
        filteredPalm.dy >= activeTop &&
        filteredPalm.dy <= activeBottom;

    // Preserve brief directional flash on Presenter View border after swipe
    if (nowMs < _flashUntilMs) {
      return HandTrackingFrame(
        phase: _flashPhase,
        armProgress: 1.0,
        estimatedDistanceMeters: estMeters,
        fps: fps,
        usingGpu: usingGpu,
        activeZoneTopNorm: activeTop,
        activeZoneBottomNorm: activeBottom,
        palmPositionNorm: filteredPalm,
        leftShoulderNorm: lSh,
        rightShoulderNorm: rSh,
        leftElbowNorm: lEl,
        rightElbowNorm: rEl,
        leftWristNorm: lWr,
        rightWristNorm: rWr,
        handLandmarksNorm: landmarks,
        extendedFingers: extendedFingers,
      );
    }

    // Cooldown state: ignore return stroke in opposite direction
    if (_state == ClutchTrackingPhase.cooldown) {
      final cooldownExpired = nowMs >= _cooldownUntilMs;
      final returnStrokeSettled = vxNorm.abs() < 0.55 ||
          (_lastSwipeSign != 0 && vxNorm.sign == _lastSwipeSign.toDouble());
      if (cooldownExpired && returnStrokeSettled) {
        _state = ClutchTrackingPhase.personIdle;
        _armAccumMs = 0.0;
      } else {
        return HandTrackingFrame(
          phase: ClutchTrackingPhase.cooldown,
          estimatedDistanceMeters: estMeters,
          fps: fps,
          usingGpu: usingGpu,
          activeZoneTopNorm: activeTop,
          activeZoneBottomNorm: activeBottom,
          palmPositionNorm: filteredPalm,
          leftShoulderNorm: lSh,
          rightShoulderNorm: rSh,
          leftElbowNorm: lEl,
          rightElbowNorm: rEl,
          leftWristNorm: lWr,
          rightWristNorm: rWr,
          handLandmarksNorm: landmarks,
          extendedFingers: extendedFingers,
        );
      }
    }

    String? triggeredGesture;
    double dispNorm = 0.0;

    if (_state == ClutchTrackingPhase.armed && filteredPalm != null) {
      // Allow slight vertical excursion & brief motion-blur fingertip loss during fast swipe
      final inArmedBand = filteredPalm.dy >= (activeTop - 0.12 * torsoScale) &&
          filteredPalm.dy <= (activeBottom + 0.18 * torsoScale);
      final withinTimeLimit = (nowMs - _armedSinceMs) <= _armedTimeoutMs;
      final palmRecentlyOpen =
          isOpenPalm || (nowMs - _lastOpenPalmSeenMs) <= _motionBlurGraceMs;

      if (!inArmedBand || !withinTimeLimit || (!palmRecentlyOpen && vxNorm.abs() < 0.35)) {
        _state = ClutchTrackingPhase.personIdle;
        _armAccumMs = 0.0;
      } else {
        dispNorm = (filteredPalm.dx - _anchorX) / torsoScale;
        final safeSens = sensitivity.clamp(0.7, 1.4);
        final dispThresh = 0.38 / safeSens;
        final velThresh = 0.92 / safeSens;

        // Re-center anchor slowly if presenter holds open palm nearly still
        if (vxNorm.abs() < 0.25 && dispNorm.abs() < 0.18) {
          _anchorX = _anchorX * 0.88 + filteredPalm.dx * 0.12;
          dispNorm = (filteredPalm.dx - _anchorX) / torsoScale;
        }

        if (dispNorm.abs() >= dispThresh &&
            vxNorm.abs() >= velThresh &&
            dispNorm.sign == vxNorm.sign) {
          final movedLeftInMirror = dispNorm < 0;
          final isNext = invertSwipe ? !movedLeftInMirror : movedLeftInMirror;
          triggeredGesture = isNext ? 'next' : 'prev';
          _lastSwipeSign = dispNorm < 0 ? -1 : 1;
          _flashPhase = isNext
              ? ClutchTrackingPhase.swipeNext
              : ClutchTrackingPhase.swipePrev;
          _flashUntilMs = nowMs + _flashHoldMs;
          _cooldownUntilMs = nowMs + _cooldownMs;
          _state = ClutchTrackingPhase.cooldown;
          _armAccumMs = 0.0;

          return HandTrackingFrame(
            phase: _flashPhase,
            armProgress: 1.0,
            swipeDisplacementNorm: dispNorm.clamp(-1.0, 1.0),
            estimatedDistanceMeters: estMeters,
            fps: fps,
            usingGpu: usingGpu,
            activeZoneTopNorm: activeTop,
            activeZoneBottomNorm: activeBottom,
            palmPositionNorm: filteredPalm,
            leftShoulderNorm: lSh,
            rightShoulderNorm: rSh,
            leftElbowNorm: lEl,
            rightElbowNorm: rEl,
            leftWristNorm: lWr,
            rightWristNorm: rWr,
            handLandmarksNorm: landmarks,
            extendedFingers: extendedFingers,
            triggeredGesture: triggeredGesture,
          );
        }
      }
    } else {
      // Idle / Arming transitions
      if (inActiveZone && isOpenPalm && vxNorm.abs() < 0.90) {
        _armAccumMs += dtSec * 1000.0;
        if (_armAccumMs >= _armDurationMs) {
          _state = ClutchTrackingPhase.armed;
          _armedSinceMs = nowMs;
          _anchorX = filteredPalm.dx;
        } else {
          _state = ClutchTrackingPhase.arming;
        }
      } else {
        _armAccumMs = max(0.0, _armAccumMs - dtSec * 1600.0);
        _state = _armAccumMs > 20.0
            ? ClutchTrackingPhase.arming
            : ClutchTrackingPhase.personIdle;
      }
    }

    final armProgress = _state == ClutchTrackingPhase.armed
        ? 1.0
        : (_armAccumMs / _armDurationMs).clamp(0.0, 1.0);

    return HandTrackingFrame(
      phase: _state,
      armProgress: armProgress,
      swipeDisplacementNorm: dispNorm.clamp(-1.0, 1.0),
      estimatedDistanceMeters: estMeters,
      fps: fps,
      usingGpu: usingGpu,
      activeZoneTopNorm: activeTop,
      activeZoneBottomNorm: activeBottom,
      palmPositionNorm: filteredPalm,
      leftShoulderNorm: lSh,
      rightShoulderNorm: rSh,
      leftElbowNorm: lEl,
      rightElbowNorm: rEl,
      leftWristNorm: lWr,
      rightWristNorm: rWr,
      handLandmarksNorm: landmarks,
      extendedFingers: extendedFingers,
      statusMessage: statusMsg,
    );
  }
}
