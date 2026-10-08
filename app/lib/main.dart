import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'map_screen.dart';
import 'onboarding_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await settings.load();
  runApp(const WaterlogWatchApp());
}

/// Severity 1..5 -> colour used for pins, chips and banners.
Color severityColor(int s) => switch (s) {
      >= 5 => const Color(0xFFB71C1C),
      4 => const Color(0xFFE53935),
      3 => const Color(0xFFFB8C00),
      2 => const Color(0xFFFDD835),
      _ => const Color(0xFF43A047),
    };

/// Text colour that stays readable on top of [severityColor].
Color onSeverity(int s) => s == 2 ? Colors.black87 : Colors.white;

/// App-wide settings, persisted on the device.
class AppSettings extends ChangeNotifier {
  String lang = 'ta';
  bool onboarded = false;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    lang = prefs.getString('lang') ?? 'ta';
    onboarded = prefs.getBool('onboarded') ?? false;
  }

  Future<void> setLang(String l) async {
    lang = l;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lang', l);
  }

  Future<void> finishOnboarding() async {
    onboarded = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarded', true);
  }
}

final settings = AppSettings();

class WaterlogWatchApp extends StatelessWidget {
  const WaterlogWatchApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF0277BD);
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) => MaterialApp(
        title: 'Waterlog Watch',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: seed),
          useMaterial3: true,
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark),
          useMaterial3: true,
        ),
        home: settings.onboarded ? const MapScreen() : const OnboardingScreen(),
      ),
    );
  }
}
