import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:window_manager/window_manager.dart';

import 'l10n/app_localizations.dart';
import 'screens/desktop_shell_screen.dart';
import 'screens/splash_screen.dart';
import 'services/locale_prefs.dart';
import 'services/onboarding_prefs.dart';
import 'services/reading_prefs.dart';
import 'services/theme_prefs.dart';
import 'theme/app_theme.dart';

bool get _isDesktop =>
    Platform.isWindows || Platform.isLinux || Platform.isMacOS;

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await ThemePrefs.load();
  await LocalePrefs.load();
  await OnboardingPrefs.load();
  await ReadingPrefs.load();

  if (_isDesktop) {
    await windowManager.ensureInitialized();
  }

  final initialFile = args.isNotEmpty ? args.first : null;
  runApp(PagelitApp(initialFilePath: initialFile));

  if (_isDesktop) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await windowManager.setSize(const Size(1280, 820));
      await windowManager.setMinimumSize(const Size(860, 560));
      await windowManager.center();
      await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
      await windowManager.show();
      await windowManager.focus();
    });
  }
}

class PagelitApp extends StatelessWidget {
  const PagelitApp({super.key, this.initialFilePath});

  final String? initialFilePath;

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
          home: _isDesktop
              ? DesktopShellScreen(initialFilePath: initialFilePath)
              : const SplashScreen(),
        ),
      ),
    );
  }
}
