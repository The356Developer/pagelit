import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/presentation_parser.dart';
import '../services/session/session_models.dart';
import '../services/slide_image_precacher.dart';
import '../widgets/presentation_stage_canvas.dart';

/// Root application widget hosted inside the secondary borderless fullscreen
/// Projector engine (`--projector`).
class ProjectorApp extends StatelessWidget {
  const ProjectorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Pagelit Projector',
      debugShowCheckedModeBanner: false,
      home: ProjectorWindowScreen(),
    );
  }
}

class ProjectorWindowScreen extends StatefulWidget {
  const ProjectorWindowScreen({super.key});

  @override
  State<ProjectorWindowScreen> createState() => _ProjectorWindowScreenState();
}

class _ProjectorWindowScreenState extends State<ProjectorWindowScreen> {
  static const MethodChannel _clientChannel =
      MethodChannel('pagelit/projector_client');

  PresentationDeck? _deck;
  String _loadedFilePath = '';
  int _loadGeneration = 0;

  final ValueNotifier<SessionStateSnapshot?> _snapshotNotifier =
      ValueNotifier<SessionStateSnapshot?>(null);

  @override
  void initState() {
    super.initState();
    _clientChannel.setMethodCallHandler(_handleHostCall);
    // Notify the C++ host that our Dart isolate is ready to receive initial state.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _clientChannel.invokeMethod<void>('clientReady').ignore();
    });
  }

  @override
  void dispose() {
    _clientChannel.setMethodCallHandler(null);
    _snapshotNotifier.dispose();
    super.dispose();
  }

  Future<dynamic> _handleHostCall(MethodCall call) async {
    if (call.method == 'syncState') {
      final raw = call.arguments;
      if (raw is Map<Object?, Object?>) {
        final snap = SessionStateSnapshot.fromMap(raw);
        _snapshotNotifier.value = snap;
        if (snap.filePath.isNotEmpty && snap.filePath != _loadedFilePath) {
          await _loadDeck(snap.filePath, snap.currentIndex);
        }
      }
    }
  }

  Future<void> _loadDeck(String filePath, int initialIndex) async {
    _loadedFilePath = filePath;
    final gen = ++_loadGeneration;
    try {
      final bytes = await File(filePath).readAsBytes();
      final parsed = await PresentationParser.parse(bytes);
      if (!mounted || gen != _loadGeneration) return;
      setState(() {
        _deck = parsed;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _deck != null) {
          SlideImagePrecacher.precacheAround(context, _deck!, initialIndex);
        }
      });
    } catch (_) {
      // Keep clean black canvas if unreadable.
    }
  }

  void _sendCommandToPresenter(SessionCommand command) {
    _clientChannel
        .invokeMethod<void>('forwardCommand', command.toMap())
        .ignore();
  }

  void _requestExit() {
    _clientChannel.invokeMethod<void>('requestClose').ignore();
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
            _sendCommandToPresenter(
              const NextStepCommand(sourceId: 'projector_kb'),
            ),
        const SingleActivator(LogicalKeyboardKey.pageDown): () =>
            _sendCommandToPresenter(
              const NextStepCommand(sourceId: 'projector_kb'),
            ),
        const SingleActivator(LogicalKeyboardKey.space): () =>
            _sendCommandToPresenter(
              const NextStepCommand(sourceId: 'projector_kb'),
            ),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
            _sendCommandToPresenter(
              const PrevStepCommand(sourceId: 'projector_kb'),
            ),
        const SingleActivator(LogicalKeyboardKey.pageUp): () =>
            _sendCommandToPresenter(
              const PrevStepCommand(sourceId: 'projector_kb'),
            ),
        const SingleActivator(LogicalKeyboardKey.keyB): () =>
            _sendCommandToPresenter(
              const ToggleBlackoutCommand(
                BlackoutMode.black,
                sourceId: 'projector_kb',
              ),
            ),
        const SingleActivator(LogicalKeyboardKey.keyW): () =>
            _sendCommandToPresenter(
              const ToggleBlackoutCommand(
                BlackoutMode.white,
                sourceId: 'projector_kb',
              ),
            ),
        const SingleActivator(LogicalKeyboardKey.escape): _requestExit,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: MouseRegion(
            cursor: SystemMouseCursors.none,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _sendCommandToPresenter(
                const NextStepCommand(sourceId: 'projector_tap'),
              ),
              onSecondaryTap: () => _sendCommandToPresenter(
                const PrevStepCommand(sourceId: 'projector_tap'),
              ),
              child: ValueListenableBuilder<SessionStateSnapshot?>(
                valueListenable: _snapshotNotifier,
                builder: (context, snapshot, _) {
                  final deck = _deck;
                  if (deck == null || snapshot == null) {
                    return const ColoredBox(
                      color: Colors.black,
                      child: SizedBox.expand(),
                    );
                  }
                  return PresentationStageCanvas(
                    deck: deck,
                    snapshot: snapshot,
                    showOptionalGestureDot: true,
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
