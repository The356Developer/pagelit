import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persisted preferences for 2–3m Far-Field Hand Tracking in Presenter Mode.
class HandTrackingPrefs {
  HandTrackingPrefs._();

  static const _keyInvertSwipe = 'ht_invert_swipe';
  static const _keySensitivity = 'ht_sensitivity';
  static const _keyProjectorDot = 'ht_projector_dot';
  static const _keyPreferredCamId = 'ht_preferred_camera_id';
  static const _keyNotesFontSize = 'presenter_notes_font_size';

  /// Default (`false`): swiping hand right-to-left in mirror view (like turning a page) = Next.
  /// When `true`: swiping left-to-right = Next.
  static final ValueNotifier<bool> invertSwipeDirection =
      ValueNotifier<bool>(false);

  /// Sensitivity multiplier (`0.75` = stricter/longer swipe, `1.0` = balanced 2–3m, `1.25` = light swipe).
  static final ValueNotifier<double> sensitivity = ValueNotifier<double>(1.0);

  /// Keeps Projector 100% clean by default (`false`). Optional subtle corner dot when `true`.
  static final ValueNotifier<bool> showProjectorDot =
      ValueNotifier<bool>(false);

  static final ValueNotifier<String?> preferredCameraId =
      ValueNotifier<String?>(null);

  static final ValueNotifier<double> speakerNotesFontSize =
      ValueNotifier<double>(18.0);

  static bool _loaded = false;

  static Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    invertSwipeDirection.value = prefs.getBool(_keyInvertSwipe) ?? false;
    sensitivity.value =
        (prefs.getDouble(_keySensitivity) ?? 1.0).clamp(0.7, 1.4);
    showProjectorDot.value = prefs.getBool(_keyProjectorDot) ?? false;
    preferredCameraId.value = prefs.getString(_keyPreferredCamId);
    speakerNotesFontSize.value =
        (prefs.getDouble(_keyNotesFontSize) ?? 18.0).clamp(13.0, 38.0);
  }

  static Future<void> setInvertSwipe(bool value) async {
    invertSwipeDirection.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyInvertSwipe, value);
  }

  static Future<void> setSensitivity(double value) async {
    final clamped = value.clamp(0.7, 1.4);
    sensitivity.value = clamped;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keySensitivity, clamped);
  }

  static Future<void> setShowProjectorDot(bool value) async {
    showProjectorDot.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyProjectorDot, value);
  }

  static Future<void> setPreferredCameraId(String? id) async {
    preferredCameraId.value = id;
    final prefs = await SharedPreferences.getInstance();
    if (id == null) {
      await prefs.remove(_keyPreferredCamId);
    } else {
      await prefs.setString(_keyPreferredCamId, id);
    }
  }

  static Future<void> setSpeakerNotesFontSize(double size) async {
    final clamped = size.clamp(13.0, 38.0);
    speakerNotesFontSize.value = clamped;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyNotesFontSize, clamped);
  }
}
