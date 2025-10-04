/// Presentation models for widgets
/// 
/// These are simple data classes used by legacy widgets for display purposes.
/// They can be constructed from v1 API models when needed.

import '../core/api/api_models.dart';

/// Sensor measurement with location info for map markers and detail sheets
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

  /// Create from v1 API Sensor and Measurement
  factory SensorMeasurement.fromV1({
    required Sensor sensor,
    required Measurement measurement,
  }) {
    return SensorMeasurement(
      sensorId: sensor.id,
      name: sensor.name,
      city: sensor.city,
      lat: sensor.lat,
      lon: sensor.lon,
      valueMm: measurement.valueMm,
      timestamp: measurement.ts,
    );
  }
}

/// Time series data point for charts
class SeriesPoint {
  SeriesPoint({required this.timestamp, required this.value});

  final DateTime timestamp;
  final double value;

  /// Create from v1 API Measurement
  factory SeriesPoint.fromV1(Measurement measurement) {
    return SeriesPoint(
      timestamp: measurement.ts,
      value: measurement.valueMm,
    );
  }
}
