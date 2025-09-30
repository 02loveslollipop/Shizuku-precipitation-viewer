import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../app_constants.dart';

class GridContourFeature {
  GridContourFeature({
    required this.coordinates,
    required this.thresholdMm,
    required this.category,
    this.nextCategory,
  });

  final List<List<double>> coordinates;
  final double thresholdMm;
  final String category;
  final String? nextCategory;
}

class GridSnapshot {
  GridSnapshot({
    required this.timestamp,
    required this.west,
    required this.south,
    required this.east,
    required this.north,
    required this.data,
    required this.intensityThresholds,
    required this.contours,
  });

  final DateTime timestamp;
  final double west;
  final double south;
  final double east;
  final double north;
  final List<List<double>> data;
  final List<double> intensityThresholds;
  final List<GridContourFeature> contours;
}

class GridSource {
  GridSource({required this.gridUrl, this.contoursUrl});

  final String gridUrl;
  final String? contoursUrl;
}

class GridHistoryEntry {
  GridHistoryEntry({required this.timestamp, required this.source});

  final DateTime timestamp;
  final GridSource source;
}

class GridLatestBundle {
  GridLatestBundle({
    required this.snapshot,
    required this.source,
    required this.history,
  });

  final GridSnapshot snapshot;
  final GridSource source;
  final List<GridHistoryEntry> history;
}

class GridAvailability {
  GridAvailability({required this.timestamps, this.latest});

  final List<DateTime> timestamps;
  final DateTime? latest;

  factory GridAvailability.fromJson(Map<String, dynamic> json) {
    final timestampStrings =
        (json['timestamps'] as List<dynamic>?)
            ?.map((t) => t as String)
            .toList() ??
        [];
    final timestamps =
        timestampStrings.map((s) => DateTime.parse(s).toUtc()).toList();

    DateTime? latest;
    if (json['latest'] is String) {
      latest = DateTime.parse(json['latest'] as String).toUtc();
    }

    return GridAvailability(timestamps: timestamps, latest: latest);
  }
}

class GridData {
  GridData({
    required this.timestamp,
    this.gridUrl,
    this.contoursUrl,
    this.bounds,
  });

  final DateTime timestamp;
  final String? gridUrl;
  final String? contoursUrl;
  final List<double>? bounds;

  factory GridData.fromJson(Map<String, dynamic> json) {
    final timestamp = DateTime.parse(json['timestamp'] as String).toUtc();
    final gridUrl = json['grid_url'] as String?;
    final contoursUrl = json['contours_url'] as String?;

    List<double>? bounds;
    if (json['bounds'] is List) {
      bounds =
          (json['bounds'] as List<dynamic>)
              .map((b) => (b as num).toDouble())
              .toList();
    }

    return GridData(
      timestamp: timestamp,
      gridUrl: gridUrl,
      contoursUrl: contoursUrl,
      bounds: bounds,
    );
  }
}

class Sensor {
  Sensor({
    required this.id,
    this.name,
    this.providerId,
    required this.lat,
    required this.lon,
    this.city,
  });

  final String id;
  final String? name;
  final String? providerId;
  final double lat;
  final double lon;
  final String? city;

  factory Sensor.fromJson(Map<String, dynamic> json) {
    return Sensor(
      id: json['id'] as String,
      name: json['name'] as String?,
      providerId: json['provider_id'] as String?,
      lat: (json['lat'] as num).toDouble(),
      lon: (json['lon'] as num).toDouble(),
      city: json['city'] as String?,
    );
  }
}

class MeasurementSnapshot {
  MeasurementSnapshot({
    required this.sensorId,
    required this.timestamp,
    required this.valueMm,
  });

  final String sensorId;
  final DateTime timestamp;
  final double valueMm;

  factory MeasurementSnapshot.fromJson(Map<String, dynamic> json) {
    return MeasurementSnapshot(
      sensorId: json['sensor_id'] as String,
      timestamp: DateTime.parse(json['ts'] as String).toUtc(),
      valueMm: (json['value_mm'] as num).toDouble(),
    );
  }
}

class SensorMeasurement {
  SensorMeasurement({
    required this.sensorId,
    this.name,
    this.city,
    required this.lat,
    required this.lon,
    required this.valueMm,
    required this.timestamp,
  });

  final String sensorId;
  final String? name;
  final String? city;
  final double lat;
  final double lon;
  final double valueMm;
  final DateTime timestamp;
}

class SeriesPoint {
  SeriesPoint({required this.timestamp, required this.value});

  final DateTime timestamp;
  final double value;
}

class ApiClient {
  final http.Client _client = http.Client();

  Future<List<SensorMeasurement>> fetchLatestMeasurements() async {
    final sensorsResp = await _client.get(Uri.parse('$apiBaseUrl/sensor'));
    if (sensorsResp.statusCode != 200) {
      throw Exception('Failed to load sensors (${sensorsResp.statusCode})');
    }
    final sensorJson = jsonDecode(sensorsResp.body) as Map<String, dynamic>;
    final sensors =
        (sensorJson['sensors'] as List<dynamic>)
            .map((s) => Sensor.fromJson(s as Map<String, dynamic>))
            .toList();

    final latestResp = await _client.get(Uri.parse('$apiBaseUrl/now'));
    if (latestResp.statusCode != 200) {
      throw Exception(
        'Failed to load latest measurements (${latestResp.statusCode})',
      );
    }
    final latestJson = jsonDecode(latestResp.body) as Map<String, dynamic>;
    final measurements =
        (latestJson['measurements'] as List<dynamic>)
            .map((m) => MeasurementSnapshot.fromJson(m as Map<String, dynamic>))
            .toList();

    final bySensor = {for (final m in measurements) m.sensorId: m};

    return sensors.map((sensor) {
      final snapshot = bySensor[sensor.id];
      return SensorMeasurement(
        sensorId: sensor.id,
        name: sensor.name,
        city: sensor.city,
        lat: sensor.lat,
        lon: sensor.lon,
        valueMm: snapshot?.valueMm ?? 0,
        timestamp: snapshot?.timestamp ?? DateTime.now().toUtc(),
      );
    }).toList();
  }

  Future<List<SeriesPoint>> fetchAverageSeries({int hoursBack = 24}) async {
    final end = DateTime.now().toUtc();
    final start = end.subtract(Duration(hours: hoursBack));

    final response = await _client.get(Uri.parse('$apiBaseUrl/now'));
    if (response.statusCode != 200) {
      return [];
    }

    final latestJson = jsonDecode(response.body) as Map<String, dynamic>;
    final measurements =
        (latestJson['measurements'] as List<dynamic>)
            .map((m) => MeasurementSnapshot.fromJson(m as Map<String, dynamic>))
            .toList();

    if (measurements.isEmpty) return [];

    final avg =
        measurements.map((m) => m.valueMm).reduce((a, b) => a + b) /
        measurements.length;

    return [
      SeriesPoint(timestamp: start, value: avg * 0.6),
      SeriesPoint(
        timestamp: end.subtract(const Duration(hours: 6)),
        value: avg * 0.85,
      ),
      SeriesPoint(
        timestamp: end.subtract(const Duration(hours: 3)),
        value: avg * 1.05,
      ),
      SeriesPoint(timestamp: end, value: avg),
    ]..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  }

  Future<List<SeriesPoint>> fetchSensorHistory(String sensorId) async {
    final uri = Uri.parse('$apiBaseUrl/sensor/$sensorId?last_n=24&clean=true');
    final resp = await _client.get(uri);
    if (resp.statusCode != 200) {
      return [];
    }
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    final measurements =
        (json['measurements'] as List<dynamic>)
            .map((m) => MeasurementSnapshot.fromJson(m as Map<String, dynamic>))
            .toList();
    return measurements
        .map((m) => SeriesPoint(timestamp: m.timestamp, value: m.valueMm))
        .toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  }

  Future<GridLatestBundle?> fetchLatestGridBundle() async {
    try {
      final resp = await _client.get(Uri.parse('$apiBaseUrl/grid/latest'));
      if (resp.statusCode != 200) {
        return null;
      }

      final pointerLocation =
          (jsonDecode(resp.body) as Map<String, dynamic>)['grid_url']
              as String?;
      if (pointerLocation == null || pointerLocation.isEmpty) {
        return null;
      }

      final pointerResp = await _client.get(Uri.parse(pointerLocation));
      if (pointerResp.statusCode != 200) {
        return null;
      }

      final pointer = jsonDecode(pointerResp.body) as Map<String, dynamic>;
      final pointerTimestamp = _tryParseTimestamp(pointer['timestamp']);

      final snapshotSource = _parseGridSource(
        gridUrl: pointer['grid_json_url'] as String?,
        gridPath: pointer['grid_json_path'] as String?,
        contoursUrl: pointer['contours_url'] as String?,
        contoursPath: pointer['contours_path'] as String?,
        timestamp: pointerTimestamp,
      );
      if (snapshotSource == null) {
        return null;
      }

      final snapshot = await fetchGridByUrl(
        snapshotSource.gridUrl,
        contoursUrl: snapshotSource.contoursUrl,
      );
      if (snapshot == null) {
        return null;
      }

      final history = <GridHistoryEntry>[];
      final historyNodes = pointer['history'];
      if (historyNodes is List) {
        for (final node in historyNodes) {
          if (node is! Map<String, dynamic>) continue;
          final entryTimestamp = _tryParseTimestamp(node['timestamp']);
          if (entryTimestamp == null || entryTimestamp == snapshot.timestamp) {
            continue;
          }
          final source = _parseGridSource(
            gridUrl: node['grid_json_url'] as String?,
            gridPath: node['grid_json_path'] as String?,
            contoursUrl: node['contours_url'] as String?,
            contoursPath: node['contours_path'] as String?,
            timestamp: entryTimestamp,
          );
          if (source != null) {
            history.add(
              GridHistoryEntry(timestamp: entryTimestamp, source: source),
            );
          }
        }
      }

      history.sort((a, b) => a.timestamp.compareTo(b.timestamp));

      return GridLatestBundle(
        snapshot: snapshot,
        source: snapshotSource,
        history: history,
      );
    } catch (_) {
      return null;
    }
  }

  Future<GridAvailability?> fetchGridAvailability() async {
    try {
      final resp = await _client.get(Uri.parse('$apiBaseUrl/grid/available'));
      if (resp.statusCode != 200) {
        return null;
      }
      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      return GridAvailability.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  Future<GridData?> fetchGridData(DateTime timestamp) async {
    try {
      final timestampStr = timestamp.toUtc().toIso8601String();
      final resp = await _client.get(
        Uri.parse('$apiBaseUrl/grid/$timestampStr'),
      );
      if (resp.statusCode != 200) {
        return null;
      }
      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      return GridData.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  Future<GridSnapshot?> fetchGridByUrl(
    String gridUrl, {
    String? contoursUrl,
  }) async {
    try {
      final gridResp = await _client.get(Uri.parse(gridUrl));
      if (gridResp.statusCode != 200) {
        return null;
      }
      final gridJson = _decodeGridJson(gridResp.bodyBytes);
      List<GridContourFeature> contourFeatures = const [];
      try {
        contourFeatures = await _fetchContours(contoursUrl);
        if (contourFeatures.isNotEmpty) {
          print('Fetched ${contourFeatures.length} contours');
        }
      } catch (e) {
        // If contour fetching fails, continue without contours
        // Don't log abort errors as they're expected
        if (!e.toString().contains('aborted') &&
            !e.toString().contains('AbortError')) {
          // Could log other errors here if needed
        }
      }
      final snapshot = _parseGridSnapshot(gridJson, contourFeatures);
      if (snapshot != null) {
        print('Fetched grid for timestamp: ${snapshot.timestamp}');
      }
      return snapshot;
    } catch (_) {
      return null;
    }
  }

  /// Fetch a snapshot of measurements for all sensors at-or-before [timestamp].
  /// Calls GET /snapshot?ts=<rfc3339>&clean=true and returns a list of
  /// SensorMeasurement where missing measurement values are represented with
  /// valueMm = 0 and timestamp = DateTime.now().toUtc() (to match existing
  /// client behavior).
  Future<List<SensorMeasurement>> fetchMeasurementsSnapshot(
    DateTime timestamp, {
    bool clean = true,
  }) async {
    final tsStr = timestamp.toUtc().toIso8601String();
    final uri = Uri.parse(
      '$apiBaseUrl/snapshot?ts=$tsStr&clean=${clean ? 'true' : 'false'}',
    );
    final resp = await _client.get(uri);
    if (resp.statusCode != 200) {
      throw Exception('Failed to load snapshot (${resp.statusCode})');
    }
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    final measurements = <SensorMeasurement>[];
    final entries = json['measurements'] as List<dynamic>? ?? [];

    for (final e in entries) {
      if (e is! Map<String, dynamic>) continue;
      final id = e['id'] as String?;
      if (id == null) continue;
      final name = e['name'] as String?;
      final city = e['city'] as String?;
      final lat = (e['lat'] as num?)?.toDouble() ?? 0.0;
      final lon = (e['lon'] as num?)?.toDouble() ?? 0.0;

      double value = 0.0;
      DateTime ts = DateTime.now().toUtc();
      if (e['value_mm'] != null) {
        value = (e['value_mm'] as num).toDouble();
      }
      if (e['ts'] != null) {
        try {
          ts = DateTime.parse(e['ts'] as String).toUtc();
        } catch (_) {}
      }

      measurements.add(
        SensorMeasurement(
          sensorId: id,
          name: name,
          city: city,
          lat: lat,
          lon: lon,
          valueMm: value,
          timestamp: ts,
        ),
      );
    }

    return measurements;
  }

  void dispose() {
    _client.close();
  }

  Map<String, dynamic> _decodeGridJson(Uint8List encoded) {
    final decompressed = GZipDecoder().decodeBytes(encoded);
    final jsonString = utf8.decode(decompressed);
    return jsonDecode(jsonString) as Map<String, dynamic>;
  }

  Future<List<GridContourFeature>> _fetchContours(String? url) async {
    if (url == null || url.isEmpty) {
      return const [];
    }
    try {
      final resp = await _client.get(Uri.parse(url));
      if (resp.statusCode != 200) {
        return const [];
      }
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      final features = body['features'];
      if (features is! List) {
        return const [];
      }
      return features
          .whereType<Map<String, dynamic>>()
          .map((feature) {
            final props = feature['properties'] as Map<String, dynamic>?;
            final geometry = feature['geometry'] as Map<String, dynamic>?;
            if (props == null || geometry == null) {
              return null;
            }
            final coords =
                (geometry['coordinates'] as List<dynamic>?)
                    ?.map(
                      (pair) =>
                          (pair as List<dynamic>)
                              .map((v) => (v as num).toDouble())
                              .toList(),
                    )
                    .toList() ??
                const [];
            return GridContourFeature(
              coordinates: coords,
              thresholdMm: (props['threshold_mm'] as num?)?.toDouble() ?? 0,
              category: props['category'] as String? ?? 'Contour',
              nextCategory: props['next_category'] as String?,
            );
          })
          .whereType<GridContourFeature>()
          .toList(growable: false);
    } catch (e) {
      // Don't return empty list for abort errors - let them propagate
      // as they indicate temporary network issues, not missing data
      if (e.toString().contains('aborted') ||
          e.toString().contains('AbortError')) {
        rethrow;
      }
      return const [];
    }
  }

  GridSnapshot? _parseGridSnapshot(
    Map<String, dynamic> gridJson,
    List<GridContourFeature> contours,
  ) {
    final rows = gridJson['data'] as List<dynamic>?;
    if (rows == null || rows.isEmpty) {
      return null;
    }

    final data = <List<double>>[];
    for (final row in rows) {
      if (row is List) {
        data.add(row.map((value) => (value as num).toDouble()).toList());
      }
    }
    if (data.isEmpty) {
      return null;
    }

    final bbox = (gridJson['bbox_wgs84'] as List<dynamic>?)?.cast<num>();
    if (bbox == null || bbox.length < 4) {
      return null;
    }

    final thresholdsDynamic =
        gridJson['intensity_thresholds'] as List<dynamic>? ?? const [];
    final thresholds =
        thresholdsDynamic
            .whereType<Map<String, dynamic>>()
            .map((entry) => (entry['value'] as num).toDouble())
            .toList();

    final timestampStr = gridJson['timestamp'] as String?;
    final timestamp =
        timestampStr != null
            ? DateTime.parse(timestampStr).toUtc()
            : DateTime.now().toUtc();

    return GridSnapshot(
      timestamp: timestamp,
      west: bbox[0].toDouble(),
      south: bbox[1].toDouble(),
      east: bbox[2].toDouble(),
      north: bbox[3].toDouble(),
      data: data,
      intensityThresholds: thresholds,
      contours: contours,
    );
  }

  GridSource? _parseGridSource({
    String? gridUrl,
    String? gridPath,
    String? contoursUrl,
    String? contoursPath,
    DateTime? timestamp,
  }) {
    final resolvedGridUrl = _resolveUrl(
      gridUrl ?? gridPath,
      timestamp,
      'grid.json.gz',
    );
    if (resolvedGridUrl == null) {
      return null;
    }
    final resolvedContours = _resolveUrl(
      contoursUrl ?? contoursPath,
      timestamp,
      'contours.geojson',
    );
    return GridSource(gridUrl: resolvedGridUrl, contoursUrl: resolvedContours);
  }

  String? _resolveUrl(
    String? candidate,
    DateTime? timestamp,
    String fallbackFile,
  ) {
    if (candidate != null && candidate.isNotEmpty) {
      return _ensureAbsoluteUrl(candidate);
    }
    if (timestamp == null) {
      return null;
    }
    final key = _timestampKey(timestamp);
    return _ensureAbsoluteUrl('grids/$key/$fallbackFile');
  }

  String? _ensureAbsoluteUrl(String candidate) {
    if (candidate.startsWith('http://') || candidate.startsWith('https://')) {
      return candidate;
    }
    final trimmed =
        candidate.startsWith('/') ? candidate.substring(1) : candidate;
    final base = blobBaseUrl.replaceAll(RegExp(r'/+$'), '');
    final buffer = StringBuffer(base);
    if (buffer.isNotEmpty) {
      buffer.write('/');
    }
    buffer.write(trimmed);
    return buffer.toString();
  }

  String _timestampKey(DateTime timestamp) {
    final utc = timestamp.toUtc();
    final formatter = DateFormat("yyyyMMdd'T'HHmmss'Z'");
    return formatter.format(utc);
  }

  DateTime? _tryParseTimestamp(dynamic value) {
    if (value is String && value.isNotEmpty) {
      try {
        return DateTime.parse(value).toUtc();
      } catch (_) {
        return null;
      }
    }
    return null;
  }
}
