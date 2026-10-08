import 'package:flutter/material.dart';

import 'l10n.dart';
import 'main.dart';
import 'map_screen.dart';

/// Three-step intro shown on first launch, with a language picker.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pages = PageController();
  int _page = 0;

  static const _icons = [Icons.map_outlined, Icons.auto_awesome, Icons.alt_route];

  Future<void> _finish() async {
    await settings.finishOnboarding();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const MapScreen()));
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final last = _page == 2;
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'ta', label: Text('தமிழ்')),
                ButtonSegment(value: 'hi', label: Text('हिन्दी')),
                ButtonSegment(value: 'en', label: Text('English')),
              ],
              selected: {settings.lang},
              onSelectionChanged: (s) => setState(() => settings.setLang(s.first)),
            ),
          ),
          Expanded(
            child: PageView.builder(
              controller: _pages,
              itemCount: 3,
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (_, i) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(color: scheme.primaryContainer, shape: BoxShape.circle),
                    child: Icon(_icons[i], size: 72, color: scheme.onPrimaryContainer),
                  ),
                  const SizedBox(height: 32),
                  Text(tr('ob${i + 1}t'), style: t.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  Text(tr('ob${i + 1}b'), style: t.bodyLarge, textAlign: TextAlign.center),
                ]),
              ),
            ),
          ),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 0; i < 3; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                margin: const EdgeInsets.all(4),
                width: i == _page ? 24 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: i == _page ? scheme.primary : scheme.outlineVariant,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
          ]),
          Padding(
            padding: const EdgeInsets.all(24),
            child: FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              onPressed: last
                  ? _finish
                  : () => _pages.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeOut),
              child: Text(last ? tr('start') : tr('next')),
            ),
          ),
        ]),
      ),
    );
  }
}
