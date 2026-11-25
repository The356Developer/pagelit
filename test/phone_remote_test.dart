import 'package:flutter_test/flutter_test.dart';
import 'package:pagelit/services/remote/phone_remote_client.dart';
import 'package:pagelit/services/remote/phone_remote_server.dart';
import 'package:pagelit/services/session/document_session_controller.dart';
import 'package:pagelit/services/session/session_models.dart';

void main() {
  test('RemotePairingTarget parses pagelit://remote URIs', () {
    final target = RemotePairingTarget.tryParse(
      'pagelit://remote?host=192.168.1.42&port=45678&token=4821',
    );
    expect(target, isNotNull);
    expect(target!.host, '192.168.1.42');
    expect(target.port, 45678);
    expect(target.token, '4821');

    expect(RemotePairingTarget.tryParse('https://example.com'), isNull);
    expect(RemotePairingTarget.tryParse('pagelit://remote?host=1.2.3.4'), isNull);
  });

  test('PhoneRemoteServer & PhoneRemoteClient sync state and dispatch commands', () async {
    final server = PhoneRemoteServer.instance;
    await server.stop();

    final controller = DocumentSessionController(
      sessionId: 'test_session',
      docKind: SessionDocumentKind.presentation,
      filePath: 'deck.pptx',
      title: 'Test Deck',
      totalCount: 3,
      metadataForIndex: (i) => SessionItemMetadata(
        title: 'Slide ${i + 1}',
        speakerNotesPlain: 'Notes for slide ${i + 1}',
      ),
      startTimerImmediately: false,
    );

    controller.registerInputSource(server);
    final sub = controller.snapshots.listen(server.broadcastState);
    final info = await server.start();
    expect(info, isNotNull);
    server.broadcastState(controller.value);

    final client = PhoneRemoteClient();

    // Wrong PIN should fail
    final badOk = await client.connect(
      RemotePairingTarget(
        host: '127.0.0.1',
        port: info!.port,
        token: '0000',
      ),
    );
    expect(badOk, isFalse);

    // Valid PIN should connect and receive initial snapshot
    final ok = await client.connect(
      RemotePairingTarget(
        host: '127.0.0.1',
        port: info.port,
        token: info.token,
      ),
    );
    expect(ok, isTrue);

    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(client.snapshot.value?.currentIndex, 0);
    expect(client.snapshot.value?.speakerNotesPlain, 'Notes for slide 1');
    expect(server.connectedClients.value, 1);

    // Send NextStepCommand from phone -> advances PC controller and syncs back
    client.sendCommand(const NextStepCommand());
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(controller.value.currentIndex, 1);
    expect(client.snapshot.value?.currentIndex, 1);
    expect(client.snapshot.value?.speakerNotesPlain, 'Notes for slide 2');

    // Send ToggleBlackoutCommand
    client.sendCommand(const ToggleBlackoutCommand(BlackoutMode.black));
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(controller.value.blackoutMode, BlackoutMode.black);
    expect(client.snapshot.value?.blackoutMode, BlackoutMode.black);

    await client.dispose();
    await sub.cancel();
    controller.unregisterInputSource(server);
    await server.stop();
    controller.dispose();
  });
}
