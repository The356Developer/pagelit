import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pagelit/services/device_pdfs.dart';
import 'package:pagelit/services/hand_tracking/clutch_swipe_recognizer.dart';
import 'package:pagelit/services/hand_tracking/hand_tracking_models.dart';
import 'package:pagelit/services/presentation_parser.dart';
import 'package:pagelit/services/session/document_session_controller.dart';
import 'package:pagelit/services/session/session_models.dart';

Uint8List _buildSyntheticPptxWithNotesAndExitAnim() {
  final archive = Archive();

  void addXml(String path, String xml) {
    final bytes = utf8.encode(xml);
    archive.addFile(ArchiveFile(path, bytes.length, bytes));
  }

  addXml(
    'ppt/presentation.xml',
    '''<?xml version="1.0" encoding="UTF-8"?>
<p:presentation xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"
                xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <p:sldSz cx="12192000" cy="6858000"/>
  <p:sldIdLst>
    <p:sldId id="256" r:id="rId1"/>
    <p:sldId id="257" r:id="rId2"/>
  </p:sldIdLst>
</p:presentation>''',
  );

  addXml(
    'ppt/_rels/presentation.xml.rels',
    '''<?xml version="1.0" encoding="UTF-8"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="slide" Target="slides/slide1.xml"/>
  <Relationship Id="rId2" Type="slide" Target="slides/slide2.xml"/>
</Relationships>''',
  );

  addXml(
    'ppt/slideLayouts/slideLayout1.xml',
    '''<?xml version="1.0" encoding="UTF-8"?>
<p:sldLayout xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"
             xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">
  <p:cSld>
    <p:spTree>
      <p:sp>
        <p:nvSpPr><p:cNvPr id="99" name="HeaderBar"/><p:nvPr/></p:nvSpPr>
        <p:spPr>
          <a:xfrm><a:off x="0" y="0"/><a:ext cx="12192000" cy="400000"/></a:xfrm>
          <a:solidFill><a:srgbClr val="1E3A8A"/></a:solidFill>
        </p:spPr>
      </p:sp>
    </p:spTree>
  </p:cSld>
</p:sldLayout>''',
  );

  addXml(
    'ppt/slides/_rels/slide1.xml.rels',
    '''<?xml version="1.0" encoding="UTF-8"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rIdLayout" Type="slideLayout" Target="../slideLayouts/slideLayout1.xml"/>
  <Relationship Id="rIdNotes" Type="notesSlide" Target="../notesSlides/notesSlide1.xml"/>
</Relationships>''',
  );

  addXml(
    'ppt/slides/slide1.xml',
    '''<?xml version="1.0" encoding="UTF-8"?>
<p:sld xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"
       xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">
  <p:cSld>
    <p:spTree>
      <p:sp>
        <p:nvSpPr>
          <p:cNvPr id="2" name="Title 1"/>
          <p:nvPr><p:ph type="title"/></p:nvPr>
        </p:nvSpPr>
        <p:spPr>
          <a:xfrm><a:off x="900000" y="600000"/><a:ext cx="10000000" cy="1200000"/></a:xfrm>
        </p:spPr>
        <p:txBody>
          <a:p><a:r><a:t>Touchless Architecture</a:t></a:r></a:p>
        </p:txBody>
      </p:sp>
      <p:sp>
        <p:nvSpPr>
          <p:cNvPr id="3" name="Callout"/>
          <p:nvPr/>
        </p:nvSpPr>
        <p:spPr>
          <a:xfrm><a:off x="900000" y="2200000"/><a:ext cx="8000000" cy="1800000"/></a:xfrm>
        </p:spPr>
        <p:txBody>
          <a:p><a:r><a:t>Animated Point</a:t></a:r></a:p>
        </p:txBody>
      </p:sp>
    </p:spTree>
  </p:cSld>
  <p:timing>
    <p:tnLst>
      <p:par>
        <p:cTn id="1" nodeType="tmRoot">
          <p:childTnLst>
            <p:seq>
              <p:cTn id="2" nodeType="mainSeq">
                <p:childTnLst>
                  <p:par>
                    <p:cTn id="3" nodeType="clickEffect" presetClass="entr" presetID="10" dur="400">
                      <p:tgtEl><p:spTgt spid="3"/></p:tgtEl>
                    </p:cTn>
                  </p:par>
                  <p:par>
                    <p:cTn id="4" nodeType="clickEffect" presetClass="exit" presetID="10" dur="350">
                      <p:tgtEl><p:spTgt spid="3"/></p:tgtEl>
                    </p:cTn>
                  </p:par>
                </p:childTnLst>
              </p:cTn>
            </p:seq>
          </p:childTnLst>
        </p:cTn>
      </p:par>
    </p:tnLst>
  </p:timing>
</p:sld>''',
  );

  addXml(
    'ppt/notesSlides/notesSlide1.xml',
    '''<?xml version="1.0" encoding="UTF-8"?>
<p:notes xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"
         xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">
  <p:cSld>
    <p:spTree>
      <p:sp>
        <p:nvSpPr><p:cNvPr id="10" name="Slide Image"/><p:nvPr><p:ph type="sldImg"/></p:nvPr></p:nvSpPr>
      </p:sp>
      <p:sp>
        <p:nvSpPr><p:cNvPr id="11" name="Notes Placeholder"/><p:nvPr><p:ph type="body" idx="1"/></p:nvPr></p:nvSpPr>
        <p:txBody>
          <a:p>
            <a:r><a:rPr b="1"/><a:t>Key takeaway:</a:t></a:r>
            <a:r><a:t> Stand 2.5m back and raise an open palm.</a:t></a:r>
          </a:p>
          <a:p>
            <a:pPr lvl="0"/>
            <a:r><a:t>Mention dual-screen 60fps sync.</a:t></a:r>
          </a:p>
        </p:txBody>
      </p:sp>
      <p:sp>
        <p:nvSpPr><p:cNvPr id="12" name="Slide Number"/><p:nvPr><p:ph type="sldNum"/></p:nvPr></p:nvSpPr>
        <p:txBody><a:p><a:r><a:t>1</a:t></a:r></a:p></p:txBody>
      </p:sp>
    </p:spTree>
  </p:cSld>
</p:notes>''',
  );

  addXml(
    'ppt/slides/slide2.xml',
    '''<?xml version="1.0" encoding="UTF-8"?>
<p:sld xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"
       xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">
  <p:cSld>
    <p:spTree>
      <p:sp>
        <p:nvSpPr><p:cNvPr id="2" name="Title 2"/><p:nvPr><p:ph type="title"/></p:nvPr></p:nvSpPr>
        <p:txBody><a:p><a:r><a:t>Second Slide</a:t></a:r></a:p></p:txBody>
      </p:sp>
    </p:spTree>
  </p:cSld>
</p:sld>''',
  );

  return Uint8List.fromList(ZipEncoder().encode(archive));
}

/// Generates synthetic 21 MediaPipe hand landmarks centered at `(cx, cy)`
/// for either an open spread palm or a closed fist.
List<double> _makeSyntheticHandLandmarks(
  double cx,
  double cy, {
  required bool openPalm,
  double scale = 0.08,
}) {
  // Wrist below center
  final wx = cx;
  final wy = cy + scale * 0.55;
  final pts = <List<double>>[];

  // 0: wrist
  pts.add([wx, wy]);

  // 1..4: thumb
  for (int j = 1; j <= 4; j++) {
    final t = openPalm ? (j * 0.25) : (j * 0.08);
    pts.add([wx - scale * (0.25 + t * 0.65), wy - scale * (0.15 + t * 0.45)]);
  }

  // 4 fingers (index, middle, ring, pinky): MCP, PIP, DIP, TIP
  const xOffsets = [-0.32, -0.10, 0.12, 0.34];
  for (final xo in xOffsets) {
    final mcpX = wx + scale * xo;
    final mcpY = wy - scale * 0.52;
    pts.add([mcpX, mcpY]); // MCP
    if (openPalm) {
      pts.add([mcpX, mcpY - scale * 0.24]); // PIP
      pts.add([mcpX, mcpY - scale * 0.44]); // DIP
      pts.add([mcpX, mcpY - scale * 0.66]); // TIP well extended!
    } else {
      // Curled fist: tips tucked near wrist/MCP
      pts.add([mcpX, mcpY - scale * 0.12]);
      pts.add([mcpX, mcpY - scale * 0.04]);
      pts.add([mcpX, mcpY + scale * 0.10]);
    }
  }

  return [for (final p in pts) ...p];
}

void main() {
  group('PresentationParser speaker notes, exit animations & master chrome', () {
    test('extracts formatted speaker notes, exit steps, and layout decor', () {
      final bytes = _buildSyntheticPptxWithNotesAndExitAnim();
      final deck = PresentationParser.parseSync(bytes);

      expect(deck.slides.length, 2);
      final s1 = deck.slides[0];
      expect(s1.title, 'Touchless Architecture');
      expect(s1.hasSpeakerNotes, isTrue);
      expect(s1.speakerNotes.length, 2);
      expect(s1.speakerNotes[0].spans.first.bold, isTrue);
      expect(s1.speakerNotesPlain, contains('Key takeaway:'));
      expect(s1.speakerNotesPlain, contains('Mention dual-screen 60fps sync.'));
      // Slide number placeholder ("1") must be excluded from speaker notes
      expect(s1.speakerNotesPlain, isNot(equals('1')));

      // Inherited decorative header bar from slideLayout1 + 2 slide shapes = 3 elements
      expect(s1.elements.length, 3);
      expect(s1.elements.first.isBackgroundDecor, isTrue);

      // Entrance (clickGroup 1) + Exit (clickGroup 2)
      expect(s1.animationClickStepCount, 2);
      expect(s1.animations.any((a) => a.isEntrance && a.clickGroup == 1), isTrue);
      expect(s1.animations.any((a) => a.isExit && a.clickGroup == 2), isTrue);
    });

    test('detects legacy OLE2 binary (.ppt/.doc/.xls) header cleanly', () {
      final ole = Uint8List.fromList(
        [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1, 0x00, 0x00],
      );
      expect(DevicePdfLibrary.isLegacyOleBinary(ole), isTrue);
      expect(
        () => PresentationParser.parseSync(ole),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('DocumentSessionController & Phone-Remote wire serialization', () {
    test('steps through animations, slides, blackout, and JSON round-trips', () {
      final deck = PresentationParser.parseSync(
        _buildSyntheticPptxWithNotesAndExitAnim(),
      );
      final controller = DocumentSessionController.forPresentation(
        deck: deck,
        filePath: 'C:/decks/demo.pptx',
        title: 'Demo',
        startTimerImmediately: false,
      );
      addTearDown(controller.dispose);

      expect(controller.value.currentIndex, 0);
      expect(controller.value.currentStep, 0);
      expect(controller.value.totalSteps, 2);
      expect(controller.value.nextItemTitle, 'Second Slide');

      // Step 1 -> Step 2 -> Slide 2
      controller.dispatch(const NextStepCommand());
      expect(controller.value.currentIndex, 0);
      expect(controller.value.currentStep, 1);

      controller.dispatch(const NextStepCommand());
      expect(controller.value.currentIndex, 0);
      expect(controller.value.currentStep, 2);

      controller.dispatch(const NextStepCommand());
      expect(controller.value.currentIndex, 1);
      expect(controller.value.currentStep, 0);

      // Blackout toggle & auto-clear on step back
      controller.dispatch(const ToggleBlackoutCommand(BlackoutMode.black));
      expect(controller.value.blackoutMode, BlackoutMode.black);

      controller.dispatch(const PrevStepCommand());
      expect(controller.value.blackoutMode, BlackoutMode.none);
      expect(controller.value.currentIndex, 0);
      expect(controller.value.currentStep, 2);

      // JSON round-trip for future Pagelit Phone App remote
      final jsonSnap = controller.value.toJson();
      final decodedSnap = SessionStateSnapshot.fromJson(jsonSnap);
      expect(decodedSnap.title, 'Demo');
      expect(decodedSnap.currentIndex, 0);
      expect(decodedSnap.currentStep, 2);
      expect(decodedSnap.speakerNotesPlain, contains('Key takeaway:'));

      final cmdJson = const JumpToIndexCommand(1, sourceId: 'phone').toJson();
      final decodedCmd = SessionCommand.fromJson(cmdJson);
      expect(decodedCmd, isA<JumpToIndexCommand>());
      controller.dispatch(decodedCmd!);
      expect(controller.value.currentIndex, 1);
    });
  });

  group('ClutchSwipeRecognizer at 2.8m far-field scale', () {
    test('ignores talking fists/low hands, arms on open palm, triggers swipe & blocks return stroke', () {
      final recognizer = ClutchSwipeRecognizer();
      // Simulated presenter standing ~2.8m away (shoulder span = 0.11, torsoScale = 0.18)
      const lSh = [0.445, 0.36];
      const rSh = [0.555, 0.36];
      const torso = 0.18;

      int t = 1000;

      // 1. Talking with closed/curled hands in active zone -> NEVER arms or triggers
      for (int i = 0; i < 15; i++) {
        t += 33;
        final x = 0.40 + (i % 5) * 0.05;
        final frame = recognizer.processRawSample({
          'timestampMs': t,
          'personDetected': true,
          'torsoScale': torso,
          'lShoulder': lSh,
          'rShoulder': rSh,
          'rWrist': [x, 0.42],
          'palm': [x, 0.40],
          'handLandmarks': _makeSyntheticHandLandmarks(
            x,
            0.40,
            openPalm: false,
            scale: 0.05,
          ),
        });
        expect(frame.triggeredGesture, isNull);
        expect(frame.phase, isNot(ClutchTrackingPhase.armed));
      }

      // 2. Raise steady Open Palm at 2.8m for ~300ms -> engages ARMED clutch
      HandTrackingFrame? armedFrame;
      for (int i = 0; i < 11; i++) {
        t += 33;
        armedFrame = recognizer.processRawSample({
          'timestampMs': t,
          'personDetected': true,
          'torsoScale': torso,
          'lShoulder': lSh,
          'rShoulder': rSh,
          'rWrist': [0.58, 0.40],
          'palm': [0.58, 0.38],
          'handLandmarks': _makeSyntheticHandLandmarks(
            0.58,
            0.38,
            openPalm: true,
            scale: 0.05,
          ),
        });
      }
      expect(armedFrame?.phase, ClutchTrackingPhase.armed);
      expect(armedFrame!.estimatedDistanceMeters, closeTo(2.8, 0.4));

      // 3. Air-swipe right-to-left in mirror view -> fires 'next'
      String? fired;
      double palmX = 0.58;
      for (int i = 0; i < 5; i++) {
        t += 33;
        palmX -= 0.032; // ~0.16 total displacement (~0.88 * torsoScale)
        final f = recognizer.processRawSample({
          'timestampMs': t,
          'personDetected': true,
          'torsoScale': torso,
          'lShoulder': lSh,
          'rShoulder': rSh,
          'rWrist': [palmX, 0.40],
          'palm': [palmX, 0.38],
          // Simulate motion blur mid-swipe (no fingertip landmarks needed once latched!)
        });
        fired ??= f.triggeredGesture;
      }
      expect(fired, 'next');

      // 4. Immediate return stroke back to right -> ignored by cooldown/return guard!
      for (int i = 0; i < 8; i++) {
        t += 33;
        palmX += 0.025;
        final f = recognizer.processRawSample({
          'timestampMs': t,
          'personDetected': true,
          'torsoScale': torso,
          'lShoulder': lSh,
          'rShoulder': rSh,
          'rWrist': [palmX, 0.40],
          'palm': [palmX, 0.38],
          'handLandmarks': _makeSyntheticHandLandmarks(
            palmX,
            0.38,
            openPalm: true,
            scale: 0.05,
          ),
        });
        expect(f.triggeredGesture, isNull);
      }
    });
  });
}
