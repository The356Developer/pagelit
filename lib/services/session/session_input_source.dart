import 'session_models.dart';

typedef SessionCommandSink = void Function(SessionCommand command);

/// Pluggable input source contract for driving a [DocumentSessionController].
///
/// Implementations include:
/// - Keyboard / hardware presenter clickers
/// - Far-field (2–3m) webcam hand gesture engine
/// - Pagelit Phone Companion remote (LAN WebSocket / BLE)
abstract class SessionInputSource {
  /// Stable identifier (e.g. `'keyboard'`, `'hand_tracking'`, `'phone_remote'`).
  String get id;

  /// Human-readable label shown in UI diagnostics.
  String get displayName;

  /// Attaches a sink that forwards commands to the active session controller.
  void attach(SessionCommandSink onCommand);

  /// Detaches from the active session controller without destroying hardware resources.
  void detach();

  /// Releases underlying resources.
  Future<void> dispose();
}
