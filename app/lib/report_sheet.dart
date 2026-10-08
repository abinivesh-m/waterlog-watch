import 'package:flutter/material.dart';

import 'api.dart';
import 'main.dart';

/// Severity + depth + who-can-pass summary used on the sheet and after submitting.
class ReportSummary extends StatelessWidget {
  final Report report;
  const ReportSummary({super.key, required this.report});

  @override
  Widget build(BuildContext context) {
    final r = report;
    final t = Theme.of(context).textTheme;
    final local = settings.lang != 'en' && r.summaryLocal.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: severityColor(r.severity), borderRadius: BorderRadius.circular(20)),
            child: Text('Severity ${r.severity}/5',
                style: TextStyle(color: r.severity == 2 ? Colors.black : Colors.white, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 8),
          Text('${r.depthLabel} · ~${r.depthCm} cm', style: t.titleMedium),
        ]),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _Passable(icon: Icons.directions_walk, label: 'Walk', ok: r.pedestrian),
          _Passable(icon: Icons.two_wheeler, label: 'Bike', ok: r.twoWheeler),
          _Passable(icon: Icons.directions_car, label: 'Car', ok: r.car),
        ]),
        const SizedBox(height: 12),
        if (local) Text(r.summaryLocal, style: t.bodyLarge),
        if (local) const SizedBox(height: 4),
        Text(r.summary, style: local ? t.bodyMedium?.copyWith(color: t.bodySmall?.color) : t.bodyLarge),
        if (r.hazards.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final h in r.hazards)
              Chip(
                avatar: const Icon(Icons.warning_amber_rounded, size: 18, color: Colors.orange),
                label: Text(h),
                visualDensity: VisualDensity.compact,
              ),
          ]),
        ],
      ],
    );
  }
}

class _Passable extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool ok;
  const _Passable({required this.icon, required this.label, required this.ok});

  @override
  Widget build(BuildContext context) {
    final c = ok ? Colors.green : Colors.red;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        border: Border.all(color: c),
        borderRadius: BorderRadius.circular(8),
        color: c.withValues(alpha: 0.08),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 18, color: c),
        const SizedBox(width: 4),
        Text(label),
        const SizedBox(width: 4),
        Icon(ok ? Icons.check_circle : Icons.cancel, size: 16, color: c),
      ]),
    );
  }
}

/// Bottom sheet for a pin on the map: photo, AI assessment and crowd votes.
class ReportSheet extends StatefulWidget {
  final Report report;
  final ValueChanged<Report> onUpdated;
  const ReportSheet({super.key, required this.report, required this.onUpdated});

  @override
  State<ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<ReportSheet> {
  late Report _r = widget.report;
  bool _busy = false;

  Future<void> _vote(String kind) async {
    setState(() => _busy = true);
    try {
      final updated = await Api.vote(_r.id, kind);
      setState(() => _r = updated);
      widget.onUpdated(updated);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(kind == 'cleared' ? 'Thanks! Marked as cleared.' : 'Thanks for confirming.'),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.62,
      maxChildSize: 0.92,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: [
          Center(
            child: Container(width: 40, height: 4, decoration: BoxDecoration(
              color: Colors.grey, borderRadius: BorderRadius.circular(2))),
          ),
          const SizedBox(height: 12),
          if (_r.photoUrl != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                aspectRatio: 4 / 3,
                child: Image.network(
                  _r.photoUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const ColoredBox(
                    color: Colors.black12, child: Center(child: Icon(Icons.image_not_supported))),
                  loadingBuilder: (c, child, p) =>
                      p == null ? child : const Center(child: CircularProgressIndicator()),
                ),
              ),
            ),
          const SizedBox(height: 16),
          ReportSummary(report: _r),
          const SizedBox(height: 12),
          Text(
            [
              'Reported ${_r.ageLabel}',
              if (_r.distanceM != null) '${(_r.distanceM! / 1000).toStringAsFixed(1)} km away',
              '${_r.stillThere} confirmed · ${_r.cleared} say cleared',
            ].join(' · '),
            style: t.bodySmall,
          ),
          if (_r.note.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('"${_r.note}"', style: t.bodyMedium?.copyWith(fontStyle: FontStyle.italic)),
          ],
          const SizedBox(height: 20),
          if (_r.status == 'cleared')
            const ListTile(leading: Icon(Icons.check_circle, color: Colors.green), title: Text('People report this spot is clear now'))
          else
            Row(children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _busy ? null : () => _vote('still_there'),
                  icon: const Icon(Icons.water),
                  label: const Text('Still flooded'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : () => _vote('cleared'),
                  icon: const Icon(Icons.check),
                  label: const Text('Cleared'),
                ),
              ),
            ]),
        ],
      ),
    );
  }
}
