import 'package:flutter/material.dart';

import 'api.dart';
import 'l10n.dart';
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
        Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, runSpacing: 6, children: [
          SeverityBadge(severity: r.severity),
          Text('${depthText(r.depth)} · ~${r.depthCm} cm', style: t.titleMedium),
        ]),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _Passable(icon: Icons.directions_walk, label: tr('walk'), ok: r.pedestrian),
          _Passable(icon: Icons.two_wheeler, label: tr('bike'), ok: r.twoWheeler),
          _Passable(icon: Icons.directions_car, label: tr('car'), ok: r.car),
        ]),
        const SizedBox(height: 12),
        if (local) Text(r.summaryLocal, style: t.bodyLarge),
        if (local) const SizedBox(height: 4),
        if (r.summary.isNotEmpty)
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

class SeverityBadge extends StatelessWidget {
  final int severity;
  const SeverityBadge({super.key, required this.severity});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: severityColor(severity), borderRadius: BorderRadius.circular(20)),
      child: Text('${tr('severity')} $severity/5',
          style: TextStyle(color: onSeverity(severity), fontWeight: FontWeight.bold)),
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

/// Opens the detail sheet for a report. [onUpdated] receives the report after a vote.
Future<void> showReportSheet(BuildContext context, Report report, ValueChanged<Report> onUpdated) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => ReportSheet(report: report, onUpdated: onUpdated),
  );
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
    final messenger = ScaffoldMessenger.of(context);
    try {
      final updated = await Api.vote(_r.id, kind);
      if (!mounted) return;
      setState(() => _r = updated);
      widget.onUpdated(updated);
      messenger.showSnackBar(SnackBar(content: Text(kind == 'cleared' ? tr('thanksCleared') : tr('thanksStill'))));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(friendlyError(e))));
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
      minChildSize: 0.3,
      maxChildSize: 0.95,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: Colors.grey, borderRadius: BorderRadius.circular(2)),
            ),
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
                  errorBuilder: (context, error, stack) => const ColoredBox(
                    color: Colors.black12,
                    child: Center(child: Icon(Icons.image_not_supported)),
                  ),
                  loadingBuilder: (context, child, progress) =>
                      progress == null ? child : const Center(child: CircularProgressIndicator()),
                ),
              ),
            ),
          if (_r.photoUrl != null) const SizedBox(height: 16),
          ReportSummary(report: _r),
          const SizedBox(height: 12),
          Text(
            [
              tr('reported', {'age': ageText(_r.ageMinutes)}),
              if (_r.distanceM != null) tr('kmAway', {'km': km(_r.distanceM)}),
              tr('votes', {'a': _r.stillThere, 'b': _r.cleared}),
            ].join(' · '),
            style: t.bodySmall,
          ),
          if (_r.note.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('"${_r.note}"', style: t.bodyMedium?.copyWith(fontStyle: FontStyle.italic)),
          ],
          const SizedBox(height: 20),
          if (_r.status == 'cleared')
            ListTile(
              leading: const Icon(Icons.check_circle, color: Colors.green),
              title: Text(tr('clearNow')),
            )
          else
            Row(children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _busy ? null : () => _vote('still_there'),
                  icon: const Icon(Icons.water),
                  label: Text(tr('still')),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : () => _vote('cleared'),
                  icon: const Icon(Icons.check),
                  label: Text(tr('cleared')),
                ),
              ),
            ]),
        ],
      ),
    );
  }
}
