import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../services/encoding_utils.dart';
import '../services/remote/phone_remote_client.dart';
import '../services/session/session_models.dart';
import '../theme/app_theme.dart';

/// Mobile companion screen that pairs with a PC Presenter View over local Wi-Fi
/// (via QR code or manual IP/Port/PIN) and acts as a live slide clicker,
/// timer, blackout toggle, and speaker-notes reader.
class PhoneRemoteScreen extends StatefulWidget {
  const PhoneRemoteScreen({super.key});

  @override
  State<PhoneRemoteScreen> createState() => _PhoneRemoteScreenState();
}

class _PhoneRemoteScreenState extends State<PhoneRemoteScreen> {
  final PhoneRemoteClient _client = PhoneRemoteClient();
  final TextEditingController _hostController = TextEditingController();
  final TextEditingController _portController =
      TextEditingController(text: '45678');
  final TextEditingController _pinController = TextEditingController();

  MobileScannerController? _scannerController;
  bool _scannerActive = true;
  bool _handlingScan = false;

  @override
  void dispose() {
    _scannerController?.dispose();
    _hostController.dispose();
    _portController.dispose();
    _pinController.dispose();
    _client.dispose();
    super.dispose();
  }

  MobileScannerController _ensureScanner() {
    return _scannerController ??= MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
    );
  }

  Future<void> _onBarcodeDetect(BarcodeCapture capture) async {
    if (_handlingScan) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null) continue;
      final target = RemotePairingTarget.tryParse(raw);
      if (target == null) continue;

      _handlingScan = true;
      HapticFeedback.mediumImpact();
      _hostController.text = target.host;
      _portController.text = target.port.toString();
      _pinController.text = target.token;

      final ok = await _client.connect(target);
      if (mounted) {
        _handlingScan = false;
        if (ok) {
          await _scannerController?.stop();
        }
      }
      break;
    }
  }

  Future<void> _connectManually() async {
    final host = _hostController.text.trim();
    final port = int.tryParse(_portController.text.trim()) ?? 0;
    final token = _pinController.text.trim();
    if (host.isEmpty || port <= 0 || token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter the PC IP address, port, and 4-digit PIN.'),
        ),
      );
      return;
    }
    FocusScope.of(context).unfocus();
    final ok = await _client.connect(
      RemotePairingTarget(host: host, port: port, token: token),
    );
    if (ok && mounted) {
      await _scannerController?.stop();
    }
  }

  void _send(SessionCommand command) {
    HapticFeedback.lightImpact();
    _client.sendCommand(command);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<RemoteConnectionStatus>(
      valueListenable: _client.status,
      builder: (context, status, _) {
        final connected = status == RemoteConnectionStatus.connected;
        return Scaffold(
          backgroundColor: connected ? const Color(0xFF111318) : null,
          appBar: AppBar(
            backgroundColor: connected ? const Color(0xFF1A1D24) : null,
            foregroundColor: connected ? Colors.white : null,
            title: Text(connected ? 'PC Remote' : 'Connect to PC'),
            actions: [
              if (connected)
                TextButton.icon(
                  onPressed: () async {
                    await _client.disconnect();
                    if (mounted && _scannerActive) {
                      unawaited(_scannerController?.start());
                    }
                  },
                  icon: const Icon(
                    Icons.link_off_rounded,
                    size: 18,
                    color: Color(0xFFF87171),
                  ),
                  label: const Text(
                    'Disconnect',
                    style: TextStyle(color: Color(0xFFF87171)),
                  ),
                ),
            ],
          ),
          body: connected
              ? _buildRemoteController()
              : _buildPairingView(status),
        );
      },
    );
  }

  Widget _buildPairingView(RemoteConnectionStatus status) {
    final scheme = Theme.of(context).colorScheme;
    final connecting = status == RemoteConnectionStatus.connecting;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppPalette.signal.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppPalette.signal.withValues(alpha: 0.25),
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.wifi_rounded, color: AppPalette.signal),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Make sure your phone and PC are on the same Wi-Fi, then open Presenter View on PC and tap Phone Remote.',
                  style: TextStyle(
                    fontSize: 13,
                    color: scheme.onSurface,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Mode switch: QR Scan vs Manual Entry
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment<bool>(
              value: true,
              icon: Icon(Icons.qr_code_scanner_rounded),
              label: Text('Scan QR'),
            ),
            ButtonSegment<bool>(
              value: false,
              icon: Icon(Icons.dialpad_rounded),
              label: Text('Manual IP'),
            ),
          ],
          selected: {_scannerActive},
          onSelectionChanged: (sel) {
            final useScanner = sel.first;
            setState(() => _scannerActive = useScanner);
            if (useScanner) {
              _scannerController?.start();
            } else {
              _scannerController?.stop();
            }
          },
        ),
        const SizedBox(height: 16),

        if (_scannerActive) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: SizedBox(
              height: 290,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  MobileScanner(
                    controller: _ensureScanner(),
                    onDetect: _onBarcodeDetect,
                  ),
                  Center(
                    child: Container(
                      width: 190,
                      height: 190,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: AppPalette.signal,
                          width: 3,
                        ),
                      ),
                    ),
                  ),
                  if (connecting)
                    Container(
                      color: Colors.black54,
                      child: const Center(
                        child: CircularProgressIndicator(),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Point the camera at the QR code shown in Pagelit on your PC.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ] else ...[
          TextField(
            controller: _hostController,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'PC IP Address',
              hintText: '192.168.1.42',
              prefixIcon: Icon(Icons.computer_rounded),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _portController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Port',
                    hintText: '45678',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _pinController,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  decoration: const InputDecoration(
                    labelText: '4-Digit PIN',
                    counterText: '',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: connecting ? null : _connectManually,
            icon: connecting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.link_rounded),
            label: Text(connecting ? 'Connecting...' : 'Connect to PC'),
          ),
        ],

        ValueListenableBuilder<String?>(
          valueListenable: _client.errorMessage,
          builder: (_, err, _) {
            if (err == null || err.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.errorContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'Connection failed: $err',
                  style: TextStyle(
                    color: scheme.onErrorContainer,
                    fontSize: 12.5,
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildRemoteController() {
    return ValueListenableBuilder<SessionStateSnapshot?>(
      valueListenable: _client.snapshot,
      builder: (context, snap, _) {
        if (snap == null) {
          return const Center(
            child: Text(
              'Connected — waiting for presentation state...',
              style: TextStyle(color: Colors.white70),
            ),
          );
        }

        final slideNum = snap.totalCount == 0 ? 0 : snap.currentIndex + 1;
        final isBlack = snap.blackoutMode == BlackoutMode.black;
        final isWhite = snap.blackoutMode == BlackoutMode.white;

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Deck header + Timer
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1D24),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF2B303B)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              EncodingUtils.cleanDisplayName(snap.title),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Slide $slideNum of ${snap.totalCount}'
                              '${snap.totalSteps > 0 ? '  •  Step ${snap.currentStep}/${snap.totalSteps}' : ''}',
                              style: const TextStyle(
                                color: Color(0xFF94A3B8),
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF252932),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _formatElapsed(snap.elapsedMs),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                            const SizedBox(width: 6),
                            GestureDetector(
                              onTap: () =>
                                  _send(const ToggleTimerPauseCommand()),
                              child: Icon(
                                snap.isTimerRunning
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                                size: 18,
                                color: Colors.white70,
                              ),
                            ),
                            const SizedBox(width: 6),
                            GestureDetector(
                              onTap: () => _send(const ResetTimerCommand()),
                              child: const Icon(
                                Icons.refresh_rounded,
                                size: 17,
                                color: Colors.white60,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Big Swipeable & Tappable Slide Pad
                GestureDetector(
                  onHorizontalDragEnd: (details) {
                    final v = details.primaryVelocity ?? 0;
                    if (v < -220) {
                      _send(const NextStepCommand());
                    } else if (v > 220) {
                      _send(const PrevStepCommand());
                    }
                  },
                  child: Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: SizedBox(
                          height: 150,
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF252932),
                              foregroundColor: Colors.white,
                              disabledBackgroundColor:
                                  const Color(0xFF1A1D24),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                            onPressed: snap.canStepBack
                                ? () => _send(const PrevStepCommand())
                                : null,
                            child: const Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.chevron_left_rounded, size: 42),
                                SizedBox(height: 4),
                                Text(
                                  'PREV',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 3,
                        child: SizedBox(
                          height: 150,
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: AppPalette.signal,
                              foregroundColor: Colors.white,
                              disabledBackgroundColor:
                                  const Color(0xFF2A1D1D),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                            onPressed: snap.canStepNext
                                ? () => _send(const NextStepCommand())
                                : null,
                            child: const Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.chevron_right_rounded, size: 52),
                                SizedBox(height: 2),
                                Text(
                                  'NEXT',
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Quick Stage Controls: Blackout, Whiteout, Replay
                Row(
                  children: [
                    Expanded(
                      child: _RemoteActionChip(
                        icon: Icons.tv_off_rounded,
                        label: 'Black',
                        active: isBlack,
                        activeColor: const Color(0xFFF59E0B),
                        onTap: () => _send(
                          const ToggleBlackoutCommand(BlackoutMode.black),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _RemoteActionChip(
                        icon: Icons.wb_sunny_outlined,
                        label: 'White',
                        active: isWhite,
                        activeColor: const Color(0xFFF59E0B),
                        onTap: () => _send(
                          const ToggleBlackoutCommand(BlackoutMode.white),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _RemoteActionChip(
                        icon: Icons.replay_rounded,
                        label: 'Replay',
                        active: false,
                        activeColor: const Color(0xFF3B82F6),
                        onTap: () => _send(const ReplayAnimationsCommand()),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Speaker Notes Card
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1D24),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFF2B303B)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.notes_rounded,
                              size: 16,
                              color: Color(0xFF94A3B8),
                            ),
                            const SizedBox(width: 6),
                            const Text(
                              'SPEAKER NOTES',
                              style: TextStyle(
                                color: Color(0xFF94A3B8),
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.8,
                              ),
                            ),
                            const Spacer(),
                            if (snap.nextItemTitle.isNotEmpty)
                              Flexible(
                                child: Text(
                                  'Next: ${snap.nextItemTitle}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xFF64748B),
                                    fontSize: 11.5,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: SingleChildScrollView(
                            child: Text(
                              snap.speakerNotesPlain.trim().isEmpty
                                  ? 'No speaker notes for this slide.'
                                  : snap.speakerNotesPlain.trim(),
                              style: TextStyle(
                                color: snap.speakerNotesPlain.trim().isEmpty
                                    ? Colors.white38
                                    : Colors.white.withValues(alpha: 0.9),
                                fontSize: 15,
                                height: 1.5,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static String _formatElapsed(int ms) {
    final totalSec = (ms / 1000).floor();
    final h = totalSec ~/ 3600;
    final m = (totalSec % 3600) ~/ 60;
    final s = totalSec % 60;
    final mm = m.toString().padLeft(2, '0');
    final ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }
}

class _RemoteActionChip extends StatelessWidget {
  const _RemoteActionChip({
    required this.icon,
    required this.label,
    required this.active,
    required this.activeColor,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final Color activeColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active
          ? activeColor.withValues(alpha: 0.2)
          : const Color(0xFF1A1D24),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: active ? activeColor : const Color(0xFF2B303B),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: active ? activeColor : Colors.white70,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: active ? activeColor : Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
