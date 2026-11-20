import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pagelit/l10n/app_localizations.dart';
import 'package:pagelit/screens/settings_screen.dart';
import 'package:pagelit/services/locale_prefs.dart';
import 'package:pagelit/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LocalePrefs', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      LocalePrefs.locale.value = null;
    });

    test('defaults to null (system default)', () async {
      await LocalePrefs.load();
      expect(LocalePrefs.locale.value, isNull);
    });

    test('saves and loads Arabic locale', () async {
      await LocalePrefs.set(const Locale('ar'));
      expect(LocalePrefs.locale.value, const Locale('ar'));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('app_language_code'), 'ar');

      LocalePrefs.locale.value = null;
      await LocalePrefs.load();
      expect(LocalePrefs.locale.value, const Locale('ar'));
    });

    test('saves and loads French locale', () async {
      await LocalePrefs.set(const Locale('fr'));
      expect(LocalePrefs.locale.value, const Locale('fr'));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('app_language_code'), 'fr');

      LocalePrefs.locale.value = null;
      await LocalePrefs.load();
      expect(LocalePrefs.locale.value, const Locale('fr'));
    });

    test('resets to system default when setting null', () async {
      await LocalePrefs.set(const Locale('ar'));
      await LocalePrefs.set(null);
      expect(LocalePrefs.locale.value, isNull);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('app_language_code'), 'system');

      await LocalePrefs.load();
      expect(LocalePrefs.locale.value, isNull);
    });
  });

  group('AppLocalizations strings', () {
    test('English strings', () async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(l10n.copiedToClipboard, 'Copied to clipboard');
      expect(l10n.precisionHighlightHint, contains('precision handles'));
      expect(l10n.geminiOpeningInBrowser, contains('Opening Gemini'));
      expect(l10n.getGeminiApp, 'Get App');
      expect(l10n.pause, 'Pause');
      expect(l10n.replayAnimation, 'Replay animation');
      expect(l10n.scanningChapters, 'Detecting chapters…');
      expect(l10n.detectedChapters, 'Auto-detected chapters');
      expect(l10n.filterChaptersHint, 'Filter chapters…');
      expect(l10n.previousPage, 'Previous page');
      expect(l10n.nextPage, 'Next page');
      expect(l10n.pageNumberLabel(3, 10), 'Page 3 / 10');
      expect(l10n.rotateScreen, 'Rotate screen');
      expect(l10n.stepXOfY(1, 4), 'Step 1/4');
    });

    test('French translations are complete and accurate', () async {
      final l10n = await AppLocalizations.delegate.load(const Locale('fr'));
      expect(l10n.openPdf, 'Ouvrir un PDF');
      expect(l10n.settings, 'Paramètres');
      expect(l10n.language, 'LANGUE');
      expect(l10n.appearance, 'APPARENCE');
      expect(l10n.welcomeTitle, 'Bienvenue sur Pagelit');
      expect(l10n.searchDocuments, 'Rechercher des documents');
      expect(l10n.onThisDevice, 'SUR CET APPAREIL');
      expect(l10n.recentFiles, 'FICHIERS RÉCENTS');
      expect(l10n.tableOfContents, 'Table des matières');
      expect(l10n.copiedToClipboard, 'Copié dans le presse-papiers');
      expect(l10n.precisionHighlightHint, contains('poignées'));
      expect(l10n.geminiOpeningInBrowser, contains('navigateur'));
      expect(l10n.getGeminiApp, "Obtenir l'app");
      expect(l10n.pause, 'Pause');
      expect(l10n.replayAnimation, "Rejouer l'animation");
      expect(l10n.scanningChapters, 'Détection des chapitres…');
      expect(l10n.detectedChapters, 'Chapitres détectés automatiquement');
      expect(l10n.filterChaptersHint, 'Filtrer les chapitres…');
      expect(l10n.previousPage, 'Page précédente');
      expect(l10n.nextPage, 'Page suivante');
      expect(l10n.pageNumberLabel(3, 10), 'Page 3 / 10');
      expect(l10n.rotateScreen, "Pivoter l'écran");
      expect(l10n.stepXOfY(1, 4), 'Étape 1/4');
    });

    test('Arabic translations are complete and accurate', () async {
      final l10n = await AppLocalizations.delegate.load(const Locale('ar'));
      expect(l10n.openPdf, 'فتح ملف PDF');
      expect(l10n.settings, 'الإعدادات');
      expect(l10n.language, 'اللغة');
      expect(l10n.appearance, 'المظهر');
      expect(l10n.welcomeTitle, 'مرحباً بك في Pagelit');
      expect(l10n.searchDocuments, 'بحث في المستندات');
      expect(l10n.onThisDevice, 'على هذا الجهاز');
      expect(l10n.recentFiles, 'الملفات الأخيرة');
      expect(l10n.tableOfContents, 'جدول المحتويات');
      expect(l10n.copiedToClipboard, 'تم النسخ إلى الحافظة');
      expect(l10n.precisionHighlightHint, contains('المقابض'));
      expect(l10n.geminiOpeningInBrowser, contains('Gemini'));
      expect(l10n.getGeminiApp, 'تثبيت التطبيق');
      expect(l10n.pause, 'إيقاف مؤقت');
      expect(l10n.replayAnimation, 'إعادة تشغيل الحركة');
      expect(l10n.scanningChapters, 'جارٍ اكتشاف الفصول…');
      expect(l10n.detectedChapters, 'فصول مكتشفة تلقائياً');
      expect(l10n.filterChaptersHint, 'تصفية الفصول…');
      expect(l10n.previousPage, 'الصفحة السابقة');
      expect(l10n.nextPage, 'الصفحة التالية');
      expect(l10n.pageNumberLabel(3, 10), 'صفحة 3 / 10');
      expect(l10n.rotateScreen, 'تدوير الشاشة');
      expect(l10n.stepXOfY(1, 4), 'الخطوة 1/4');
    });
  });

  group('Widget Localization & Language Switcher', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      LocalePrefs.locale.value = null;
    });

    testWidgets('Settings screen shows language section and switches to Arabic', (tester) async {
      await tester.pumpWidget(
        ValueListenableBuilder<Locale?>(
          valueListenable: LocalePrefs.locale,
          builder: (context, locale, _) => MaterialApp(
            theme: AppTheme.light(),
            locale: locale,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: const SettingsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initially English
      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('LANGUAGE'), findsOneWidget);
      expect(find.text('System Default'), findsOneWidget);
      expect(find.text('Français'), findsOneWidget);
      expect(find.text('العربية'), findsOneWidget);

      // Switch to Arabic
      await tester.tap(find.text('العربية'));
      await tester.pumpAndSettle();

      // Now Settings title is in Arabic!
      expect(find.text('الإعدادات'), findsOneWidget);
      expect(find.text('اللغة'), findsOneWidget);
      expect(find.text('المظهر'), findsOneWidget);
      expect(find.text('القراءة'), findsOneWidget);
      expect(LocalePrefs.locale.value, const Locale('ar'));

      // Switch to French
      await tester.tap(find.text('Français'));
      await tester.pumpAndSettle();

      expect(find.text('Paramètres'), findsOneWidget);
      expect(find.text('LANGUE'), findsOneWidget);
      expect(find.text('APPARENCE'), findsOneWidget);
      expect(find.text('LECTURE'), findsOneWidget);
      expect(LocalePrefs.locale.value, const Locale('fr'));
    });

    testWidgets('Settings screen renders without overflow on narrow 320px device in all locales', (tester) async {
      // Simulate narrow 320px device
      tester.view.physicalSize = const Size(320 * 2.0, 568 * 2.0);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      for (final locale in [const Locale('en'), const Locale('fr'), const Locale('ar')]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            locale: locale,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: const SettingsScreen(),
          ),
        );
        await tester.pumpAndSettle();
        // Verifies no exception / RenderFlex overflow was thrown
        expect(tester.takeException(), isNull, reason: 'Failed with overflow in locale $locale');
      }
    });
  });
}
