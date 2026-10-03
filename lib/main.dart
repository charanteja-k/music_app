import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'services/audio_handler.dart';
import 'screens/intro_splash_screen.dart';
import 'services/preferences_service.dart';
import 'services/bug_report_service.dart';
import 'widgets/keyboard_playback_controller.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb) {
    try {
      await initAudioService();
    } catch (e) {
      debugPrint('AudioService init warning: $e');
    }
  }
  await PreferencesService().init();
  await BugReportService.instance.init();
  runApp(const MusicApp());
}

class MusicApp extends StatelessWidget {
  const MusicApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: PreferencesService(),
      builder: (context, child) {
        final prefs = PreferencesService();
        return MaterialApp(
          title: 'DilSe',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            brightness: Brightness.dark,
            scaffoldBackgroundColor: const Color(0xFF121212),
            primaryColor: prefs.themeColor,
            bottomNavigationBarTheme: BottomNavigationBarThemeData(
              backgroundColor: Colors.black,
              selectedItemColor: prefs.themeColor,
              unselectedItemColor: Colors.white54,
            ),
            appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xFF121212),
              elevation: 0,
            ),
            tooltipTheme: TooltipThemeData(
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E2C),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.14),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.45),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              textStyle: const TextStyle(
                color: Colors.white,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
              waitDuration: const Duration(milliseconds: 300),
              showDuration: const Duration(milliseconds: 1500),
            ),
            useMaterial3: true,
          ),
          navigatorKey: BugReportService.instance.rootNavKey,
          builder: (context, child) {
            final appChild = KeyboardPlaybackController(
              child: child ?? const SizedBox.shrink(),
            );
            if (kIsWeb) {
              return appChild;
            }
            return RepaintBoundary(
              key: BugReportService.instance.repaintBoundaryKey,
              child: appChild,
            );
          },
          home: const IntroSplashScreen(),
        );
      },
    );
  }
}
