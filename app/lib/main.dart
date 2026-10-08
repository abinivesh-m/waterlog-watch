import 'package:flutter/material.dart';

import 'map_screen.dart';

void main() => runApp(const WaterlogWatchApp());

/// Severity 1..5 -> colour used for pins, chips and banners.
Color severityColor(int s) => switch (s) {
      >= 5 => const Color(0xFFB71C1C),
      4 => const Color(0xFFE53935),
      3 => const Color(0xFFFB8C00),
      2 => const Color(0xFFFDD835),
      _ => const Color(0xFF43A047),
    };

/// Shared app state: preferred language for AI summaries.
class AppSettings extends ChangeNotifier {
  String lang = 'ta';
  void setLang(String l) {
    lang = l;
    notifyListeners();
  }
}

final settings = AppSettings();

class WaterlogWatchApp extends StatelessWidget {
  const WaterlogWatchApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF0277BD);
    return MaterialApp(
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
      home: const MapScreen(),
    );
  }
}
