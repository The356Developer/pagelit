import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'l10n/app_localizations.dart';
import 'screens/splash_screen.dart';
import 'services/locale_prefs.dart';
import 'services/onboarding_prefs.dart';
import 'services/reading_prefs.dart';
import 'services/theme_prefs.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ThemePrefs.load();
  await LocalePrefs.load();
  await OnboardingPrefs.load();
  await ReadingPrefs.load();
  runApp(const PagelitApp());
}

class PagelitApp extends StatelessWidget {
  const PagelitApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale?>(
      valueListenable: LocalePrefs.locale,
      builder: (context, locale, _) => ValueListenableBuilder<ThemeMode>(
        valueListenable: ThemePrefs.mode,
        builder: (context, themeMode, _) => MaterialApp(
          title: 'Pagelit',
          debugShowCheckedModeBanner: false,
          themeMode: themeMode,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          locale: locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const SplashScreen(),
        ),
      ),
    );
  }
}
