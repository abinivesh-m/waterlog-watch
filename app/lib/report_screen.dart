import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'api.dart';
import 'main.dart';
import 'report_sheet.dart';

/// Take a photo of a flooded street -> Bedrock assesses it -> report goes on the map.
class ReportScreen extends StatefulWidget {
  final double lat, lng;
  const ReportScreen({super.key, required this.lat, required this.lng});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  final _note = TextEditingController();
  Uint8List? _image;
  bool _sending = false;
  String? _error;
  Report? _result;
  bool _merged = false;

  Future<void> _pick(ImageSource source) async {
    final file = await ImagePicker().pickImage(
      source: source,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 80,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() {
      _image = bytes;
      _error = null;
      _result = null;
    });
  }

  Future<void> _submit() async {
    if (_image == null) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final (report, merged) = await Api.submit(
        imageBytes: _image!,
        lat: widget.lat,
        lng: widget.lng,
        note: _note.text.trim(),
        lang: settings.lang,
      );
      setState(() {
        _result = report;
        _merged = merged;
      });
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Report flooding')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (_image == null) ...[
            Icon(Icons.water_drop_outlined, size: 72, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 12),
            Text('Take a clear photo of the waterlogged street.', style: t.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Text('Include a kerb, tyre or person so the AI can judge the depth.',
                style: t.bodyMedium, textAlign: TextAlign.center),
          ] else
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.memory(_image!, height: 260, fit: BoxFit.cover),
            ),
          const SizedBox(height: 16),
          if (_result == null) ...[
            Row(children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: _sending ? null : () => _pick(ImageSource.camera),
                  icon: const Icon(Icons.photo_camera),
                  label: const Text('Camera'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: _sending ? null : () => _pick(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library),
                  label: const Text('Gallery'),
                ),
              ),
            ]),
            const SizedBox(height: 16),
            TextField(
              controller: _note,
              maxLength: 200,
              decoration: const InputDecoration(
                labelText: 'Landmark or note (optional)',
                hintText: 'e.g. Near Usman Road bus stop',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Text('Location: ${widget.lat.toStringAsFixed(5)}, ${widget.lng.toStringAsFixed(5)}', style: t.bodySmall),
            const SizedBox(height: 16),
            if (_error != null)
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(padding: const EdgeInsets.all(12), child: Text(_error!)),
              ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _image == null || _sending ? null : _submit,
              icon: _sending
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.auto_awesome),
              label: Text(_sending ? 'AI is checking the photo…' : 'Analyse & report'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            ),
          ] else ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    const Icon(Icons.check_circle, color: Colors.green),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _merged ? 'Already reported here. We counted your confirmation.' : 'Reported! Others nearby can now see it.',
                        style: t.titleMedium,
                      ),
                    ),
                  ]),
                  const SizedBox(height: 16),
                  ReportSummary(report: _result!),
                ]),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              child: const Text('Back to map'),
            ),
          ],
        ],
      ),
    );
  }
}
