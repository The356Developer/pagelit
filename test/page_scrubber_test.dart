import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pagelit/l10n/app_localizations.dart';
import 'package:pagelit/widgets/page_scrubber.dart';

Widget _wrapScrubber({
  required Widget child,
  Locale locale = const Locale('en'),
}) {
  return MaterialApp(
    locale: locale,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: child,
        ),
      ),
    ),
  );
}

void main() {
  group('PageScrubber', () {
    testWidgets('step buttons increment/decrement and clamp at boundaries', (tester) async {
      int currentPage = 1;
      final selectedPages = <int>[];

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            return _wrapScrubber(
              child: PageScrubber(
                currentPage: currentPage,
                totalPages: 10,
                onPageSelected: (p) {
                  selectedPages.add(p);
                  setState(() => currentPage = p);
                },
              ),
            );
          },
        ),
      );
      await tester.pumpAndSettle();

      // Previous is disabled at page 1
      await tester.tap(find.byKey(const ValueKey('page_scrubber_prev')));
      await tester.pump();
      expect(selectedPages, isEmpty);

      // Next steps to page 2
      await tester.tap(find.byKey(const ValueKey('page_scrubber_next')));
      await tester.pump();
      expect(selectedPages, [2]);
      expect(currentPage, 2);

      // Previous steps back to page 1
      await tester.tap(find.byKey(const ValueKey('page_scrubber_prev')));
      await tester.pump();
      expect(selectedPages, [2, 1]);
      expect(currentPage, 1);
    });

    testWidgets('dragging updates floating preview bubble with chapter subtitle and commits on release', (tester) async {
      int? committedPage;
      final scrubbed = <int>[];

      await tester.pumpWidget(
        _wrapScrubber(
          child: PageScrubber(
            currentPage: 1,
            totalPages: 50,
            chapterPages: const [1, 15, 35],
            labelBuilder: (p) => 'Page $p / 50',
            subtitleBuilder: (p) => p >= 35 ? 'Chapter 3' : (p >= 15 ? 'Chapter 2' : 'Chapter 1'),
            enableLiveJump: false,
            onScrubChanged: scrubbed.add,
            onPageSelected: (p) => committedPage = p,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final scrubberBox =
          tester.getRect(find.byKey(const ValueKey('page_scrubber_track')));
      final startPoint = Offset(scrubberBox.left + 12, scrubberBox.center.dy);
      final gesture = await tester.startGesture(startPoint);
      await tester.pump();

      // Drag across to ~80% of the track width
      await gesture.moveBy(Offset(scrubberBox.width * 0.78, 0));
      await tester.pump();

      expect(find.byKey(const ValueKey('page_scrubber_preview_bubble')), findsOneWidget);
      expect(find.text('Chapter 3'), findsOneWidget);
      expect(scrubbed.isNotEmpty, isTrue);
      expect(scrubbed.last, greaterThan(30));
      expect(committedPage, isNull);

      await gesture.up();
      await tester.pumpAndSettle();

      // Bubble dismisses and page is committed
      expect(find.byKey(const ValueKey('page_scrubber_preview_bubble')), findsNothing);
      expect(committedPage, isNotNull);
      expect(committedPage!, greaterThan(30));
    });

    testWidgets('renders without overflow at 320px width in EN, FR, and AR (RTL)', (tester) async {
      tester.view.physicalSize = const Size(320 * 2.0, 568 * 2.0);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      for (final locale in [const Locale('en'), const Locale('fr'), const Locale('ar')]) {
        await tester.pumpWidget(
          _wrapScrubber(
            locale: locale,
            child: PageScrubber(
              currentPage: 120,
              totalPages: 450,
              chapterPages: const [1, 50, 120, 300],
              onPageSelected: (_) {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: 'PageScrubber overflowed in locale $locale at 320px',
        );
      }

      // Verify RTL horizontal drag moves toward page 1 when dragging right in Arabic
      int? rtlPage;
      await tester.pumpWidget(
        _wrapScrubber(
          locale: const Locale('ar'),
          child: PageScrubber(
            currentPage: 1,
            totalPages: 20,
            enableLiveJump: false,
            onPageSelected: (p) => rtlPage = p,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final trackRect =
          tester.getRect(find.byKey(const ValueKey('page_scrubber_track')));
      // In RTL, page 1 starts on the RIGHT and dragging LEFT increases page number
      final gesture = await tester.startGesture(
        Offset(trackRect.right - 14, trackRect.center.dy),
      );
      await tester.pump();
      await gesture.moveBy(Offset(-trackRect.width * 0.7, 0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(rtlPage, isNotNull);
      expect(rtlPage!, greaterThan(10));
    });
  });
}
