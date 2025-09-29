import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;

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

  Future<GridSnapshot?> fetchLatestGrid() async {
    try {
      final resp = await _client.get(Uri.parse('$apiBaseUrl/grid/latest'));
      if (resp.statusCode != 200) {
        return null;
      }

      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      final gridUrl = body['grid_url'] as String?;
      if (gridUrl == null || gridUrl.isEmpty) {
        return null;
      }

      final pointerResp = await _client.get(Uri.parse(gridUrl));
      if (pointerResp.statusCode != 200) {
        return null;
      }

      final pointerJson = jsonDecode(pointerResp.body) as Map<String, dynamic>;
      final gridJsonUrl = pointerJson['grid_json_url'] as String?;
      final contoursUrl = pointerJson['contours_url'] as String?;
      if (gridJsonUrl == null || gridJsonUrl.isEmpty) {
        return null;
      }

      final gridResp = await _client.get(Uri.parse(gridJsonUrl));
      if (gridResp.statusCode != 200) {
        return null;
      }
      final gridBytes = gridResp.bodyBytes;
      final decompressed = utf8.decode(GZipDecoder().decodeBytes(gridBytes));
      final gridJson = jsonDecode(decompressed) as Map<String, dynamic>;

      final data = <List<double>>[];
      final rows = gridJson['data'] as List<dynamic>?;
      if (rows != null) {
        for (final row in rows) {
          final list =
              (row as List<dynamic>)
                  .map((value) => (value as num).toDouble())
                  .toList();
          data.add(list);
        }
      }

      if (data.isEmpty) {
        return null;
      }

      final bbox = (gridJson['bbox_wgs84'] as List<dynamic>).cast<num>();
      final west = bbox[0].toDouble();
      final south = bbox[1].toDouble();
      final east = bbox[2].toDouble();
      final north = bbox[3].toDouble();

      final thresholdsDynamic =
          gridJson['intensity_thresholds'] as List<dynamic>? ?? const [];
      final thresholds =
          thresholdsDynamic
              .map((entry) => (entry['value'] as num).toDouble())
              .toList();

      final timestampStr = gridJson['timestamp'] as String?;
      final timestamp =
          timestampStr != null
              ? DateTime.parse(timestampStr).toUtc()
              : DateTime.now().toUtc();

      final contourFeatures = <GridContourFeature>[];
      if (contoursUrl != null && contoursUrl.isNotEmpty) {
        final contourResp = await _client.get(Uri.parse(contoursUrl));
        if (contourResp.statusCode == 200) {
          final contourJson =
              jsonDecode(contourResp.body) as Map<String, dynamic>;
          final features = contourJson['features'] as List<dynamic>?;
          if (features != null) {
            for (final feature in features) {
              final props = feature['properties'] as Map<String, dynamic>?;
              final geometry = feature['geometry'] as Map<String, dynamic>?;
              if (props == null || geometry == null) {
                continue;
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
              contourFeatures.add(
                GridContourFeature(
                  coordinates: coords,
                  thresholdMm: (props['threshold_mm'] as num?)?.toDouble() ?? 0,
                  category: props['category'] as String? ?? 'Contour',
                  nextCategory: props['next_category'] as String?,
                ),
              );
            }
          }
        }
      }

      return GridSnapshot(
        timestamp: timestamp,
        west: west,
        south: south,
        east: east,
        north: north,
        data: data,
        intensityThresholds: thresholds,
        contours: contourFeatures,
      );
    } catch (_) {
      return null;
    }
  }

  void dispose() {
    _client.close();
  }
}
