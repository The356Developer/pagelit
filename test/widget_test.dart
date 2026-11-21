import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pagelit/l10n/app_localizations.dart';
import 'package:pagelit/screens/reader_screen.dart';
import 'package:pagelit/services/recent_files.dart';

void main() {
  test('RecentFile JSON roundtrip', () {
    final file = RecentFile(
      path: '/storage/emulated/0/Download/example.pdf',
      name: 'example.pdf',
      openedAt: DateTime(2026, 10, 15, 12, 30),
    );
    final restored = RecentFile.fromJson(file.toJson());
    expect(restored.path, file.path);
    expect(restored.name, file.name);
    expect(restored.openedAt, file.openedAt);
  });

  testWidgets('ReaderScreen AppBar renders cleanly on narrow viewports without RenderFlex overflow', (tester) async {
    tester.view.physicalSize = const Size(240, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      const MaterialApp(
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: ReaderScreen(
          filePath: 'nonexistent_sample.pdf',
          title: 'Very Long Document Title (4).pdf',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(tester.takeException(), isNull);
  });
}
