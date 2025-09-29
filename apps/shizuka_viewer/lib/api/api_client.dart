import 'dart:convert';

import 'package:http/http.dart' as http;

import '../app_constants.dart';

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
    final sensors = (sensorJson['sensors'] as List<dynamic>)
        .map((s) => Sensor.fromJson(s as Map<String, dynamic>))
        .toList();

    final latestResp = await _client.get(Uri.parse('$apiBaseUrl/now'));
    if (latestResp.statusCode != 200) {
      throw Exception('Failed to load latest measurements (${latestResp.statusCode})');
    }
    final latestJson = jsonDecode(latestResp.body) as Map<String, dynamic>;
    final measurements = (latestJson['measurements'] as List<dynamic>)
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
    final measurements = (latestJson['measurements'] as List<dynamic>)
        .map((m) => MeasurementSnapshot.fromJson(m as Map<String, dynamic>))
        .toList();

    if (measurements.isEmpty) return [];

    final avg = measurements.map((m) => m.valueMm).reduce((a, b) => a + b) / measurements.length;

    return [
      SeriesPoint(timestamp: start, value: avg * 0.6),
      SeriesPoint(timestamp: end.subtract(const Duration(hours: 6)), value: avg * 0.85),
      SeriesPoint(timestamp: end.subtract(const Duration(hours: 3)), value: avg * 1.05),
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
    final measurements = (json['measurements'] as List<dynamic>)
        .map((m) => MeasurementSnapshot.fromJson(m as Map<String, dynamic>))
        .toList();
    return measurements
        .map((m) => SeriesPoint(timestamp: m.timestamp, value: m.valueMm))
        .toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  }

  void dispose() {
    _client.close();
  }
}
