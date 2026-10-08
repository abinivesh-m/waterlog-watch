import 'package:flutter/material.dart';

import 'api.dart';
import 'l10n.dart';
import 'main.dart';
import 'report_sheet.dart';

/// Nearby reports ranked by severity, then distance. Pull to refresh.
class ListScreen extends StatefulWidget {
  final double lat, lng;
  final List<Report> initial;
  const ListScreen({super.key, required this.lat, required this.lng, required this.initial});

  @override
  State<ListScreen> createState() => _ListScreenState();
}

class _ListScreenState extends State<ListScreen> {
  late List<Report> _reports = widget.initial;

  Future<void> _refresh() async {
    try {
      final r = await Api.nearby(widget.lat, widget.lng, radiusKm: 10);
      if (mounted) setState(() => _reports = r);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(tr('list'))),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: _reports.isEmpty
            ? ListView(children: [
                const SizedBox(height: 120),
                const Icon(Icons.wb_sunny_outlined, size: 64, color: Colors.amber),
                const SizedBox(height: 12),
                Center(child: Text(tr('noReports'), style: t.titleMedium)),
              ])
            : ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: _reports.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final r = _reports[i];
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: severityColor(r.severity),
                      child: Text('${r.severity}',
                          style: TextStyle(color: onSeverity(r.severity), fontWeight: FontWeight.bold)),
                    ),
                    title: Text(
                      r.note.isNotEmpty ? r.note : depthText(r.depth),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${depthText(r.depth)} · ${tr('kmAway', {'km': km(r.distanceM)})} · ${ageText(r.ageMinutes)}',
                    ),
                    trailing: r.car ? null : const Icon(Icons.no_crash, color: Colors.red),
                    onTap: () => showReportSheet(context, r, (u) {
                      setState(() {
                        _reports = [for (final x in _reports) if (x.id == u.id) u else x]
                            .where((x) => x.status == 'active')
                            .toList();
                      });
                    }),
                  );
                },
              ),
      ),
    );
  }
}
