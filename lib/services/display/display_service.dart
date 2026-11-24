import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import 'display_models.dart';

/// Platform-agnostic monitor enumeration & hot-plug service.
///
/// Implemented natively on Windows via Win32 `EnumDisplayMonitors` and
/// `WM_DISPLAYCHANGE`, with clean interface ready for Linux/macOS backends.
abstract class DisplayService {
  static final DisplayService instance = _createPlatformInstance();

  static DisplayService _createPlatformInstance() {
    if (Platform.isWindows) {
      return WindowsDisplayService();
    }
    return FallbackDisplayService();
  }

  /// Queries all connected physical displays.
  Future<List<DisplayInfo>> getDisplays();

  /// Emits updated display lists whenever monitors/projectors are connected or disconnected.
  Stream<List<DisplayInfo>> get onDisplaysChanged;
}

class WindowsDisplayService implements DisplayService {
  WindowsDisplayService() {
    _eventsChannel.receiveBroadcastStream().listen((event) {
      if (event is List) {
        final displays = event
            .whereType<Map<Object?, Object?>>()
            .map(DisplayInfo.fromMap)
            .toList();
        _displaysChangedController.add(displays);
      }
    });
  }

  static const MethodChannel _channel = MethodChannel('pagelit/projector');
  static const EventChannel _eventsChannel =
      EventChannel('pagelit/display_events');

  final StreamController<List<DisplayInfo>> _displaysChangedController =
      StreamController<List<DisplayInfo>>.broadcast();

  @override
  Stream<List<DisplayInfo>> get onDisplaysChanged =>
      _displaysChangedController.stream;

  @override
  Future<List<DisplayInfo>> getDisplays() async {
    try {
      final raw = await _channel.invokeMethod<List<Object?>>('getDisplays');
      if (raw == null || raw.isEmpty) {
        return _defaultSingleDisplay();
      }
      return raw
          .whereType<Map<Object?, Object?>>()
          .map(DisplayInfo.fromMap)
          .toList();
    } on PlatformException {
      return _defaultSingleDisplay();
    } on MissingPluginException {
      return _defaultSingleDisplay();
    }
  }

  List<DisplayInfo> _defaultSingleDisplay() => const [
        DisplayInfo(
          id: 'primary',
          name: 'Primary Display',
          left: 0,
          top: 0,
          width: 1920,
          height: 1080,
          workLeft: 0,
          workTop: 0,
          workWidth: 1920,
          workHeight: 1040,
          scaleFactor: 1.0,
          isPrimary: true,
        ),
      ];
}

class FallbackDisplayService implements DisplayService {
  @override
  Stream<List<DisplayInfo>> get onDisplaysChanged => const Stream.empty();

  @override
  Future<List<DisplayInfo>> getDisplays() async => const [
        DisplayInfo(
          id: 'primary',
          name: 'Primary Display',
          left: 0,
          top: 0,
          width: 1920,
          height: 1080,
          workLeft: 0,
          workTop: 0,
          workWidth: 1920,
          workHeight: 1080,
          scaleFactor: 1.0,
          isPrimary: true,
        ),
      ];
}
