import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'l10n.dart';

/// Monsoon safety tips and one-tap emergency calls.
class SafetyScreen extends StatelessWidget {
  const SafetyScreen({super.key});

  Future<void> _call(BuildContext context, String number) async {
    final ok = await launchUrl(Uri(scheme: 'tel', path: number));
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(number)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(tr('safetyTitle'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: scheme.errorContainer,
            child: ListTile(
              leading: Icon(Icons.emergency, color: scheme.onErrorContainer),
              title: Text(tr('call112'), style: TextStyle(color: scheme.onErrorContainer, fontWeight: FontWeight.bold)),
              trailing: Icon(Icons.call, color: scheme.onErrorContainer),
              onTap: () => _call(context, '112'),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.support_agent),
              title: Text(tr('call1913')),
              trailing: const Icon(Icons.call),
              onTap: () => _call(context, '1913'),
            ),
          ),
          const SizedBox(height: 8),
          for (final (i, icon) in const [
            (1, Icons.waves),
            (2, Icons.electric_bolt),
            (3, Icons.warning_amber_rounded),
            (4, Icons.subway),
            (5, Icons.battery_charging_full),
          ])
            Card(
              child: ListTile(
                leading: Icon(icon, color: scheme.primary),
                title: Text(tr('tip$i')),
              ),
            ),
        ],
      ),
    );
  }
}
