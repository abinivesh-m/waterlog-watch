import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'api.dart';
import 'l10n.dart';
import 'list_screen.dart';
import 'main.dart';
import 'report_screen.dart';
import 'report_sheet.dart';
import 'safety_screen.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  static const _chennai = LatLng(13.0418, 80.2341); // T. Nagar, used until GPS responds
  final _map = MapController();
  LatLng _me = _chennai;
  bool _haveGps = false;
  List<Report> _reports = [];
  bool _loading = true;
  String? _error;
  Timer? _timer;

  LatLng? _destination;
  RouteResult? _route;
  bool _checkingRoute = false;
  String _mode = 'scooter'; // most commuters at risk in floods are on two-wheelers

  @override
  void initState() {
    super.initState();
    _init();
    _timer = Timer.periodic(const Duration(seconds: 60), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    await _locate();
    await _load();
  }

  void _safeMove(LatLng p, double zoom) {
    try {
      _map.move(p, zoom);
    } catch (_) {
      // Map not laid out yet; initialCenter covers this case.
    }
  }

  Future<void> _locate() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
      if (p == LocationPermission.denied || p == LocationPermission.deniedForever) return;
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)),
      );
      if (!mounted) return;
      setState(() {
        _me = LatLng(pos.latitude, pos.longitude);
        _haveGps = true;
      });
      _safeMove(_me, 14);
    } catch (_) {
      // Keep the default centre; the app still works for browsing.
    }
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final reports = await Api.nearby(_me.latitude, _me.longitude, radiusKm: 10);
      if (!mounted) return;
      setState(() {
        _reports = reports;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      if (!silent) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted && !silent) setState(() => _loading = false);
    }
  }

  Future<void> _checkRoute(LatLng dest) async {
    setState(() {
      _destination = dest;
      _route = null;
      _checkingRoute = true;
    });
    try {
      final res = await Api.routeCheck(_me.latitude, _me.longitude, dest.latitude, dest.longitude, mode: _mode);
      if (!mounted) return;
      setState(() => _route = res);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      setState(() => _destination = null);
    } finally {
      if (mounted) setState(() => _checkingRoute = false);
    }
  }

  void _replace(Report u) {
    setState(() {
      _reports = [for (final x in _reports) if (x.id == u.id) u else x].where((x) => x.status == 'active').toList();
    });
  }

  void _openReport(Report r) => showReportSheet(context, r, _replace);

  Future<void> _newReport() async {
    if (!_haveGps) {
      await _locate();
      if (!_haveGps) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('locationNeeded'))));
        return;
      }
    }
    if (!mounted) return;
    final added = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => ReportScreen(lat: _me.latitude, lng: _me.longitude)),
    );
    if (added == true) _load();
  }

  /// Soft glow under each pin, larger and stronger for worse flooding.
  List<CircleMarker> get _glow => [
        for (final r in _reports)
          CircleMarker(
            point: LatLng(r.lat, r.lng),
            radius: 80.0 + r.severity * 70,
            useRadiusInMeter: true,
            color: severityColor(r.severity).withValues(alpha: 0.22),
            borderStrokeWidth: 0,
          ),
      ];

  List<Marker> get _markers => [
        for (final r in _reports)
          Marker(
            point: LatLng(r.lat, r.lng),
            width: 44,
            height: 44,
            child: GestureDetector(
              onTap: () => _openReport(r),
              child: Container(
                decoration: BoxDecoration(
                  color: severityColor(r.severity),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                  boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black26)],
                ),
                child: Center(
                  child: Text('${r.severity}',
                      style: TextStyle(color: onSeverity(r.severity), fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
            ),
          ),
        Marker(
          point: _me,
          width: 22,
          height: 22,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.blue,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: const [BoxShadow(blurRadius: 6, color: Colors.black26)],
            ),
          ),
        ),
        if (_destination != null)
          Marker(
            point: _destination!,
            width: 40,
            height: 40,
            alignment: Alignment.topCenter,
            child: const Icon(Icons.flag, color: Colors.black87, size: 36),
          ),
      ];

  String _statusText() {
    if (_reports.isEmpty) return tr('none');
    final severe = _reports.where((r) => r.severity >= 4).length;
    final base = _reports.length == 1 ? tr('nearby1') : tr('nearby', {'n': _reports.length});
    return severe > 0 ? '$base · ${tr('dangerous', {'n': severe})}' : base;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Waterlog Watch'),
        actions: [
          IconButton(
            icon: const Icon(Icons.health_and_safety_outlined),
            tooltip: tr('safety'),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SafetyScreen())),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.translate),
            tooltip: tr('language'),
            initialValue: settings.lang,
            onSelected: (l) => setState(() => settings.setLang(l)),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'ta', child: Text('தமிழ்')),
              PopupMenuItem(value: 'hi', child: Text('हिन्दी')),
              PopupMenuItem(value: 'en', child: Text('English')),
            ],
          ),
          IconButton(icon: const Icon(Icons.refresh), tooltip: tr('refresh'), onPressed: _load),
        ],
      ),
      body: Stack(children: [
        FlutterMap(
          mapController: _map,
          options: MapOptions(
            initialCenter: _chennai,
            initialZoom: 13,
            onLongPress: (_, point) => _checkRoute(point),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.waterlogwatch.waterlog_watch',
            ),
            CircleLayer(circles: _glow),
            if (_destination != null)
              PolylineLayer(polylines: [
                Polyline(
                  points: _route != null && _route!.path.length >= 2
                      ? [for (final p in _route!.path) LatLng(p[0], p[1])]
                      : [_me, _destination!],
                  strokeWidth: 6,
                  color: _route == null
                      ? Colors.grey
                      : severityColor(_route!.worstSeverity == 0 ? 1 : _route!.worstSeverity),
                ),
              ]),
            MarkerLayer(markers: _markers),
            const RichAttributionWidget(attributions: [TextSourceAttribution('OpenStreetMap contributors')]),
          ],
        ),
        Positioned(
          top: 12,
          left: 12,
          right: 12,
          child: Card(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: _reports.isEmpty
                  ? null
                  : () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ListScreen(lat: _me.latitude, lng: _me.longitude, initial: _reports),
                        ),
                      ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: _loading
                    ? Row(children: [
                        const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                        const SizedBox(width: 12),
                        Text(tr('loading')),
                      ])
                    : _error != null
                        ? Row(children: [
                            Icon(Icons.cloud_off, color: scheme.error),
                            const SizedBox(width: 12),
                            Expanded(child: Text(_error!)),
                          ])
                        : Row(children: [
                            Icon(Icons.water, color: scheme.primary),
                            const SizedBox(width: 12),
                            Expanded(child: Text(_statusText())),
                            if (_reports.isNotEmpty) ...[
                              Text(tr('list'), style: TextStyle(color: scheme.primary)),
                              Icon(Icons.chevron_right, color: scheme.primary),
                            ],
                          ]),
              ),
            ),
          ),
        ),
        if (_destination != null) Positioned(left: 12, right: 12, bottom: 96, child: _routeCard()),
        if (_destination == null && !_loading)
          Positioned(
            left: 16,
            right: 16,
            bottom: 100,
            child: Center(child: Chip(avatar: const Icon(Icons.touch_app, size: 18), label: Text(tr('hint')))),
          ),
      ]),
      floatingActionButton: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
        FloatingActionButton.small(
          heroTag: 'me',
          tooltip: tr('myLocation'),
          onPressed: () async {
            await _locate();
            _safeMove(_me, 15);
            _load(silent: true);
          },
          child: const Icon(Icons.my_location),
        ),
        const SizedBox(height: 12),
        FloatingActionButton.extended(
          heroTag: 'report',
          onPressed: _newReport,
          icon: const Icon(Icons.add_a_photo),
          label: Text(tr('report')),
        ),
      ]),
    );
  }

  Widget _routeCard() {
    final r = _route;
    final color = r == null ? Colors.grey : severityColor(r.worstSeverity == 0 ? 1 : r.worstSeverity);
    final verdict = r?.verdict;
    final title = switch (verdict) {
      'avoid' || 'caution' || 'minor' || 'clear' => tr(verdict!),
      _ => tr('checking'),
    };
    return Card(
      shape: RoundedRectangleBorder(side: BorderSide(color: color, width: 2), borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 4, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Icon(verdict == 'clear' ? Icons.check_circle : Icons.alt_route, color: color),
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => setState(() {
                _destination = null;
                _route = null;
              }),
            ),
          ]),
          Padding(
            padding: const EdgeInsets.only(right: 12, bottom: 8),
            child: SegmentedButton<String>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: 'scooter', icon: const Icon(Icons.two_wheeler), label: Text(tr('bike'))),
                ButtonSegment(value: 'car', icon: const Icon(Icons.directions_car), label: Text(tr('car'))),
                ButtonSegment(value: 'pedestrian', icon: const Icon(Icons.directions_walk), label: Text(tr('walk'))),
              ],
              selected: {_mode},
              onSelectionChanged: (s) {
                setState(() => _mode = s.first);
                if (_destination != null) _checkRoute(_destination!);
              },
            ),
          ),
          if (_checkingRoute) const LinearProgressIndicator(),
          if (r != null) ...[
            Text(tr('${r.verdict}Adv')),
            const SizedBox(height: 4),
            Text(
              [
                tr('onRoute', {'km': km(r.routeLengthM), 'n': r.spots.length}),
                if (r.durationS != null) tr('mins', {'n': (r.durationS! / 60).ceil()}),
              ].join(' · '),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            for (final s in r.spots.take(3))
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  radius: 12,
                  backgroundColor: severityColor(s.severity),
                  child: Text('${s.severity}', style: TextStyle(fontSize: 12, color: onSeverity(s.severity))),
                ),
                title: Text('${depthText(s.depth)} · ${tr('ahead', {'km': km(s.distanceM)})}'),
                subtitle: s.note.isNotEmpty ? Text(s.note, maxLines: 1, overflow: TextOverflow.ellipsis) : null,
                onTap: () => _openReport(s),
              ),
          ],
        ]),
      ),
    );
  }
}
