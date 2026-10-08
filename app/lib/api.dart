import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Set at build time:  flutter build apk --dart-define=API_URL=https://xxxx.execute-api.ap-south-1.amazonaws.com
const String apiUrl = String.fromEnvironment('API_URL', defaultValue: 'https://REPLACE-ME.execute-api.ap-south-1.amazonaws.com');

class ApiError implements Exception {
  final int status;
  final String message;
  ApiError(this.status, this.message);
  @override
  String toString() => message;
}

String friendlyError(Object e) {
  if (e is ApiError) {
    if (e.status >= 500) return 'Server problem. Please try again in a moment.';
    return e.message;
  }
  if (e is TimeoutException) return 'Request timed out. Check your connection.';
  final t = e.toString();
  if (t.contains('SocketException') || t.contains('ClientException') || t.contains('Failed host lookup')) {
    return 'No internet connection.';
  }
  return 'Something went wrong. Please try again.';
}

class Report {
  final String id;
  final double lat, lng;
  final String status, depth, summary, summaryLocal, note;
  final int severity, depthCm, stillThere, cleared, ageMinutes;
  final int? distanceM, offRouteM;
  final bool pedestrian, twoWheeler, car;
  final List<String> hazards;
  final String? photoUrl;

  Report.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        lat = (j['lat'] as num).toDouble(),
        lng = (j['lng'] as num).toDouble(),
        status = (j['status'] ?? 'active') as String,
        depth = (j['depth'] ?? 'none') as String,
        summary = (j['summary'] ?? '') as String,
        summaryLocal = (j['summary_local'] ?? '') as String,
        note = (j['note'] ?? '') as String,
        severity = (j['severity'] ?? 1) as int,
        depthCm = (j['depth_cm_estimate'] ?? 0) as int,
        stillThere = (j['still_there'] ?? 0) as int,
        cleared = (j['cleared'] ?? 0) as int,
        ageMinutes = (j['age_minutes'] ?? 0) as int,
        distanceM = j['distance_m'] as int?,
        offRouteM = j['off_route_m'] as int?,
        pedestrian = (j['passable']?['pedestrian'] ?? true) as bool,
        twoWheeler = (j['passable']?['two_wheeler'] ?? true) as bool,
        car = (j['passable']?['car'] ?? true) as bool,
        hazards = ((j['hazards'] ?? []) as List).map((e) => e.toString()).toList(),
        photoUrl = j['photo_url'] as String?;
}

class RouteResult {
  final String verdict, advice, source;
  final int worstSeverity, routeLengthM, blockedSpots;
  final int? durationS;
  final List<Report> spots;

  /// Road geometry as [lat, lng] pairs (straight line if routing was unavailable).
  final List<List<double>> path;

  RouteResult.fromJson(Map<String, dynamic> j)
      : verdict = j['verdict'] as String,
        advice = j['advice'] as String,
        source = (j['routing_source'] ?? 'straight-line') as String,
        worstSeverity = j['worst_severity'] as int,
        routeLengthM = j['route_length_m'] as int,
        blockedSpots = (j['blocked_spots'] ?? 0) as int,
        durationS = j['duration_s'] as int?,
        spots = ((j['spots'] ?? []) as List).map((e) => Report.fromJson(e as Map<String, dynamic>)).toList(),
        path = ((j['path'] ?? []) as List)
            .map((p) => [((p as List)[0] as num).toDouble(), (p[1] as num).toDouble()])
            .toList();
}

class Api {
  static String? _deviceId;

  static Future<String> deviceId() async {
    if (_deviceId != null) return _deviceId!;
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString('device_id');
    if (id == null) {
      final r = Random.secure();
      id = 'dev-${List.generate(16, (_) => r.nextInt(16).toRadixString(16)).join()}';
      await prefs.setString('device_id', id);
    }
    return _deviceId = id;
  }

  static dynamic _decode(http.Response r) {
    final body = r.body.isEmpty ? null : jsonDecode(utf8.decode(r.bodyBytes));
    if (r.statusCode >= 200 && r.statusCode < 300) return body;
    final detail = body is Map && body['detail'] != null ? body['detail'].toString() : 'Request failed (${r.statusCode})';
    throw ApiError(r.statusCode, detail);
  }

  static Future<List<Report>> nearby(double lat, double lng, {double radiusKm = 5}) async {
    final r = await http
        .get(Uri.parse('$apiUrl/reports/nearby?lat=$lat&lng=$lng&radius_km=$radiusKm'))
        .timeout(const Duration(seconds: 20));
    final j = _decode(r) as Map<String, dynamic>;
    return (j['reports'] as List).map((e) => Report.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Returns (report, mergedIntoExisting).
  static Future<(Report, bool)> submit({
    required List<int> imageBytes,
    required double lat,
    required double lng,
    String note = '',
    String lang = 'ta',
  }) async {
    final r = await http
        .post(Uri.parse('$apiUrl/reports'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'image_base64': base64Encode(imageBytes),
              'lat': lat,
              'lng': lng,
              'note': note,
              'lang': lang,
              'device_id': await deviceId(),
            }))
        .timeout(const Duration(seconds: 40));
    final j = _decode(r) as Map<String, dynamic>;
    return (Report.fromJson(j['report'] as Map<String, dynamic>), j['merged_into_existing'] == true);
  }

  static Future<Report> vote(String id, String vote) async {
    final r = await http
        .post(Uri.parse('$apiUrl/reports/$id/vote'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'device_id': await deviceId(), 'vote': vote}))
        .timeout(const Duration(seconds: 20));
    return Report.fromJson(_decode(r) as Map<String, dynamic>);
  }

  /// [mode] is 'car', 'scooter' or 'pedestrian'.
  static Future<RouteResult> routeCheck(double fLat, double fLng, double tLat, double tLng,
      {String mode = 'car'}) async {
    final r = await http
        .get(Uri.parse('$apiUrl/route-check?from_lat=$fLat&from_lng=$fLng&to_lat=$tLat&to_lng=$tLng&mode=$mode'))
        .timeout(const Duration(seconds: 20));
    return RouteResult.fromJson(_decode(r) as Map<String, dynamic>);
  }
}
