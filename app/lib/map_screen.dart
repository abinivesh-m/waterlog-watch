import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'api.dart';
import 'main.dart';
import 'report_screen.dart';
import 'report_sheet.dart';

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

  Future<void> _locate() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
      if (p == LocationPermission.denied || p == LocationPermission.deniedForever) return;
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)),
      );
      setState(() {
        _me = LatLng(pos.latitude, pos.longitude);
        _haveGps = true;
      });
      _safeMove(_me, 14);
    } catch (_) {
      // Keep the default centre; the app still works for browsing.
    }
  }

  void _safeMove(LatLng p, double zoom) {
    try {
      _map.move(p, zoom);
    } catch (_) {
      // Map not laid out yet; initialCenter covers this case.
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
      final res = await Api.routeCheck(_me.latitude, _me.longitude, dest.latitude, dest.longitude);
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

  void _openReport(Report r) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      builder: (_) => ReportSheet(
        report: r,
        onUpdated: (u) => setState(() {
          _reports = [for (final x in _reports) if (x.id == u.id) u else x]
              .where((x) => x.status == 'active')
              .toList();
        }),
      ),
    );
  }

  Future<void> _newReport() async {
    if (!_haveGps) {
      await _locate();
      if (!_haveGps) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Turn on location so your report lands in the right place.'),
        ));
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
                      style: TextStyle(
                          color: r.severity == 2 ? Colors.black : Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16)),
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final severe = _reports.where((r) => r.severity >= 4).length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Waterlog Watch'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.translate),
            tooltip: 'AI summary language',
            initialValue: settings.lang,
            onSelected: (l) => setState(() => settings.setLang(l)),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'ta', child: Text('தமிழ் + English')),
              PopupMenuItem(value: 'hi', child: Text('हिन्दी + English')),
              PopupMenuItem(value: 'en', child: Text('English only')),
            ],
          ),
          IconButton(icon: const Icon(Icons.refresh), tooltip: 'Refresh', onPressed: _load),
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
              userAgentPackageName: 'com.waterlogwatch.app',
            ),
            if (_destination != null)
              PolylineLayer(polylines: [
                Polyline(
                  points: [_me, _destination!],
                  strokeWidth: 5,
                  color: _route == null ? Colors.grey : severityColor(_route!.worstSeverity == 0 ? 1 : _route!.worstSeverity),
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
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: _loading
                  ? const Row(children: [
                      SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                      SizedBox(width: 12),
                      Text('Loading flood reports…'),
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
                          Expanded(
                            child: Text(
                              _reports.isEmpty
                                  ? 'No waterlogging reported within 10 km.'
                                  : '${_reports.length} flooded spot${_reports.length == 1 ? '' : 's'} nearby'
                                      '${severe > 0 ? ' · $severe dangerous' : ''}',
                            ),
                          ),
                        ]),
            ),
          ),
        ),
        if (_destination != null)
          Positioned(left: 12, right: 12, bottom: 96, child: _routeCard()),
        if (_destination == null && !_loading)
          const Positioned(
            left: 0,
            right: 0,
            bottom: 100,
            child: Center(
              child: Chip(label: Text('Long-press anywhere to check your route')),
            ),
          ),
      ]),
      floatingActionButton: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
        FloatingActionButton.small(
          heroTag: 'me',
          tooltip: 'My location',
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
          label: const Text('Report flooding'),
        ),
      ]),
    );
  }

  Widget _routeCard() {
    final r = _route;
    final color = r == null ? Colors.grey : severityColor(r.worstSeverity == 0 ? 1 : r.worstSeverity);
    final title = switch (r?.verdict) {
      'avoid' => 'Avoid this route',
      'caution' => 'Caution on this route',
      'minor' => 'Minor water on route',
      'clear' => 'Route looks clear',
      _ => 'Checking route…',
    };
    return Card(
      shape: RoundedRectangleBorder(side: BorderSide(color: color, width: 2), borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 4, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Icon(r?.verdict == 'clear' ? Icons.check_circle : Icons.alt_route, color: color),
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
          if (_checkingRoute) const LinearProgressIndicator(),
          if (r != null) ...[
            Text(r.advice),
            const SizedBox(height: 4),
            Text('${(r.routeLengthM / 1000).toStringAsFixed(1)} km straight-line · ${r.spots.length} reported spot(s) on the way',
                style: Theme.of(context).textTheme.bodySmall),
            for (final s in r.spots.take(3))
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(radius: 12, backgroundColor: severityColor(s.severity), child: Text('${s.severity}', style: const TextStyle(fontSize: 12))),
                title: Text('${s.depthLabel} · ${((s.distanceM ?? 0) / 1000).toStringAsFixed(1)} km ahead'),
                subtitle: s.note.isNotEmpty ? Text(s.note, maxLines: 1, overflow: TextOverflow.ellipsis) : null,
                onTap: () => _openReport(s),
              ),
          ],
        ]),
      ),
    );
  }
}
