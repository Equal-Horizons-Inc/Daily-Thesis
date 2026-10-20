import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'screens/paper_screen.dart';
import 'screens/onboarding_screen.dart';
import 'services/analytics_service.dart';
import 'services/profile_storage.dart';
import 'services/text_scale_storage.dart';
import 'services/theme_mode_storage.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ThemeModeController.instance.load();
  await TextScaleController.instance.load();

  // Firebase configuration is provisioned separately for each iOS bundle ID.
  // A missing or invalid configuration must not prevent the reading app from
  // launching; analytics simply remain unavailable.
  try {
    await Firebase.initializeApp();
    await AnalyticsService.instance.initialize();
    AnalyticsService.instance.logAppOpen();
  } catch (error) {
    debugPrint('Firebase is unavailable: $error');
  }
  runApp(const DailyThesisApp());
}

class DailyThesisApp extends StatelessWidget {
  const DailyThesisApp({super.key});

  static final ThemeData _lightTheme = buildAppTheme(
    AppPalette.light,
    Brightness.light,
  );
  static final ThemeData _darkTheme = buildAppTheme(
    AppPalette.dark,
    Brightness.dark,
  );

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeModeController.instance.notifier,
      builder: (context, themeMode, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'DailyThesis',
          theme: _lightTheme,
          darkTheme: _darkTheme,
          themeMode: themeMode,
          themeAnimationDuration: Duration.zero,
          builder: (context, child) {
            final brightness = switch (themeMode) {
              ThemeMode.dark => Brightness.dark,
              ThemeMode.light => Brightness.light,
              ThemeMode.system => MediaQuery.platformBrightnessOf(context),
            };
            final palette = brightness == Brightness.dark
                ? AppPalette.dark
                : AppPalette.light;
            final icons = brightness == Brightness.dark
                ? Brightness.light
                : Brightness.dark;

            return AnnotatedRegion<SystemUiOverlayStyle>(
              value: SystemUiOverlayStyle(
                statusBarColor: Colors.transparent,
                statusBarIconBrightness: icons,
                statusBarBrightness: brightness,
                systemNavigationBarColor: palette.background,
                systemNavigationBarIconBrightness: icons,
              ),
              child: ValueListenableBuilder<AppTextScale>(
                valueListenable: TextScaleController.instance.notifier,
                builder: (context, textScale, _) {
                  return MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: TextScaler.linear(textScale.factor)),
                    child: child ?? const SizedBox.shrink(),
                  );
                },
              ),
            );
          },
          home: const AppRoot(),
        );
      },
    );
  }
}

class AppRoot extends StatefulWidget {
  const AppRoot({super.key});

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> {
  final _storage = ProfileStorage();
  bool? _hasProfile; // null = still checking

  @override
  void initState() {
    super.initState();
    _checkProfile();
  }

  Future<void> _checkProfile() async {
    final has = await _storage.hasProfile();
    setState(() => _hasProfile = has);
  }

  @override
  Widget build(BuildContext context) {
    if (_hasProfile == null) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: const SizedBox(),
      );
    }

    if (_hasProfile == false) {
      return OnboardingScreen(
        onComplete: () => setState(() => _hasProfile = true),
      );
    }

    return const PaperScreen();
  }
}
