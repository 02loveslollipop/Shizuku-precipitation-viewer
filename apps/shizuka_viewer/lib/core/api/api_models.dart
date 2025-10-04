/// API v1 Response Models
/// 
/// These models match the new /api/v1 endpoint structure.

// ============================================================================
// Pagination Models
// ============================================================================

class Pagination {
  final int page;
  final int limit;
  final int total;
  final int totalPages;

  Pagination({
    required this.page,
    required this.limit,
    required this.total,
    required this.totalPages,
  });

  factory Pagination.fromJson(Map<String, dynamic> json) {
    return Pagination(
      page: json['page'] as int,
      limit: json['limit'] as int,
      total: json['total'] as int,
      totalPages: json['total_pages'] as int,
    );
  }
}

class PaginatedResponse<T> {
  final List<T> data;
  final Pagination pagination;

  PaginatedResponse({
    required this.data,
    required this.pagination,
  });
}

// ============================================================================
// Sensor Models
// ============================================================================

class Sensor {
  final String id;
  final String name;
  final String? providerId;
  final double lat;
  final double lon;
  final double? elevationM;
  final String? city;
  final String? subbasin;
  final String? barrio;
  final Map<String, dynamic>? metadata;
  final DateTime createdAt;
  final DateTime updatedAt;

  Sensor({
    required this.id,
    required this.name,
    this.providerId,
    required this.lat,
    required this.lon,
    this.elevationM,
    this.city,
    this.subbasin,
    this.barrio,
    this.metadata,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Sensor.fromJson(Map<String, dynamic> json) {
    return Sensor(
      id: json['id'] as String,
      name: json['name'] as String,
      providerId: json['provider_id'] as String?,
      lat: (json['lat'] as num).toDouble(),
      lon: (json['lon'] as num).toDouble(),
      elevationM: json['elevation_m'] != null 
          ? (json['elevation_m'] as num).toDouble() 
          : null,
      city: json['city'] as String?,
      subbasin: json['subbasin'] as String?,
      barrio: json['barrio'] as String?,
      metadata: json['metadata'] as Map<String, dynamic>?,
      createdAt: DateTime.parse(json['created_at'] as String).toUtc(),
      updatedAt: DateTime.parse(json['updated_at'] as String).toUtc(),
    );
  }
}

class PaginatedSensors extends PaginatedResponse<Sensor> {
  PaginatedSensors({
    required List<Sensor> sensors,
    required Pagination pagination,
  }) : super(data: sensors, pagination: pagination);

  factory PaginatedSensors.fromJson(Map<String, dynamic> json) {
    final sensorsJson = json['sensors'] as List<dynamic>;
    final sensors = sensorsJson.map((s) => Sensor.fromJson(s as Map<String, dynamic>)).toList();
    final pagination = Pagination.fromJson(json['pagination'] as Map<String, dynamic>);
    
    return PaginatedSensors(
      sensors: sensors,
      pagination: pagination,
    );
  }
}

// ============================================================================
// Measurement Models
// ============================================================================

class Measurement {
  final DateTime ts;
  final double valueMm;
  final int? qcFlags;
  final String? imputationMethod;

  Measurement({
    required this.ts,
    required this.valueMm,
    this.qcFlags,
    this.imputationMethod,
  });

  factory Measurement.fromJson(Map<String, dynamic> json) {
    return Measurement(
      ts: DateTime.parse(json['ts'] as String).toUtc(),
      valueMm: (json['value_mm'] as num).toDouble(),
      qcFlags: json['qc_flags'] as int?,
      imputationMethod: json['imputation_method'] as String?,
    );
  }
}

class SensorMeasurements {
  final String sensorId;
  final bool clean;
  final int count;
  final List<Measurement> measurements;

  SensorMeasurements({
    required this.sensorId,
    required this.clean,
    required this.count,
    required this.measurements,
  });

  factory SensorMeasurements.fromJson(Map<String, dynamic> json) {
    final measurementsJson = json['measurements'] as List<dynamic>;
    final measurements = measurementsJson
        .map((m) => Measurement.fromJson(m as Map<String, dynamic>))
        .toList();
    
    return SensorMeasurements(
      sensorId: json['sensor_id'] as String,
      clean: json['clean'] as bool,
      count: json['count'] as int,
      measurements: measurements,
    );
  }
}

// ============================================================================
// Grid Models
// ============================================================================

class SensorAggregate {
  final String sensorId;
  final double avgMmH;
  final int measurementCount;
  final double minValueMm;
  final double maxValueMm;
  
  // Optional: enriched with sensor info
  Sensor? sensor;

  SensorAggregate({
    required this.sensorId,
    required this.avgMmH,
    required this.measurementCount,
    required this.minValueMm,
    required this.maxValueMm,
    this.sensor,
  });

  factory SensorAggregate.fromJson(Map<String, dynamic> json) {
    return SensorAggregate(
      sensorId: json['sensor_id'] as String,
      avgMmH: (json['avg_mm_h'] as num).toDouble(),
      measurementCount: json['measurement_count'] as int,
      minValueMm: (json['min_value_mm'] as num).toDouble(),
      maxValueMm: (json['max_value_mm'] as num).toDouble(),
    );
  }
}

class GridTimestamp {
  final DateTime ts;
  final int gridRunId;
  final int resolutionM;
  final String status;
  final List<double>? bounds;
  final String? crs;
  final String? gridUrl;
  final String? npzUrl;
  final String? contoursUrl;
  final DateTime? createdAt;
  final List<SensorAggregate>? sensors;

  GridTimestamp({
    required this.ts,
    required this.gridRunId,
    required this.resolutionM,
    required this.status,
    this.bounds,
    this.crs,
    this.gridUrl,
    this.npzUrl,
    this.contoursUrl,
    this.createdAt,
    this.sensors,
  });

  factory GridTimestamp.fromJson(Map<String, dynamic> json) {
    List<double>? bounds;
    if (json['bounds'] != null) {
      bounds = (json['bounds'] as List<dynamic>)
          .map((b) => (b as num).toDouble())
          .toList();
    }

    List<SensorAggregate>? sensors;
    if (json['sensors'] != null) {
      sensors = (json['sensors'] as List<dynamic>)
          .map((s) => SensorAggregate.fromJson(s as Map<String, dynamic>))
          .toList();
    }

    return GridTimestamp(
      ts: DateTime.parse(json['ts'] as String).toUtc(),
      gridRunId: json['grid_run_id'] as int,
      resolutionM: json['resolution_m'] as int,
      status: json['status'] as String,
      bounds: bounds,
      crs: json['crs'] as String?,
      gridUrl: json['grid_url'] as String?,
      npzUrl: json['npz_url'] as String?,
      contoursUrl: json['contours_url'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String).toUtc()
          : null,
      sensors: sensors,
    );
  }
}

class PaginatedGridTimestamps extends PaginatedResponse<GridTimestamp> {
  PaginatedGridTimestamps({
    required List<GridTimestamp> timestamps,
    required Pagination pagination,
  }) : super(data: timestamps, pagination: pagination);

  factory PaginatedGridTimestamps.fromJson(Map<String, dynamic> json) {
    final timestampsJson = json['timestamps'] as List<dynamic>;
    final timestamps = timestampsJson
        .map((t) => GridTimestamp.fromJson(t as Map<String, dynamic>))
        .toList();
    final pagination = Pagination.fromJson(json['pagination'] as Map<String, dynamic>);
    
    return PaginatedGridTimestamps(
      timestamps: timestamps,
      pagination: pagination,
    );
  }
}

/// Grid data for map display (compatible with legacy widgets)
class GridData {
  final DateTime timestamp;
  final String? gridUrl;
  final String? contoursUrl;
  final List<double>? bounds;

  GridData({
    required this.timestamp,
    this.gridUrl,
    this.contoursUrl,
    this.bounds,
  });

  /// Create from GridTimestamp
  factory GridData.fromGridTimestamp(GridTimestamp grid) {
    return GridData(
      timestamp: grid.ts,
      gridUrl: grid.gridUrl,
      contoursUrl: grid.contoursUrl,
      bounds: grid.bounds,
    );
  }

  /// Create from LatestGrid
  factory GridData.fromLatestGrid(LatestGrid grid, {List<double>? bounds}) {
    return GridData(
      timestamp: grid.ts,
      gridUrl: grid.gridUrl,
      contoursUrl: grid.contoursUrl,
      bounds: bounds,
    );
  }
}

class LatestGrid {
  final DateTime ts;
  final int gridRunId;
  final String? gridUrl;
  final String? contoursUrl;

  LatestGrid({
    required this.ts,
    required this.gridRunId,
    this.gridUrl,
    this.contoursUrl,
  });

  factory LatestGrid.fromJson(Map<String, dynamic> json) {
    return LatestGrid(
      ts: DateTime.parse(json['ts'] as String).toUtc(),
      gridRunId: json['grid_run_id'] as int,
      gridUrl: json['grid_url'] as String?,
      contoursUrl: json['contours_url'] as String?,
    );
  }
}

// ============================================================================
// Real-time Models
// ============================================================================

class RealtimeMeasurement {
  final String sensorId;
  final DateTime ts;
  final double valueMm;
  final int? qcFlags;
  
  // Optional: enriched with sensor info
  Sensor? sensor;

  RealtimeMeasurement({
    required this.sensorId,
    required this.ts,
    required this.valueMm,
    this.qcFlags,
    this.sensor,
  });

  factory RealtimeMeasurement.fromJson(Map<String, dynamic> json) {
    return RealtimeMeasurement(
      sensorId: json['sensor_id'] as String,
      ts: DateTime.parse(json['ts'] as String).toUtc(),
      valueMm: (json['value_mm'] as num).toDouble(),
      qcFlags: json['qc_flags'] as int?,
    );
  }
}

class RealtimeMeasurements {
  final DateTime timestamp;
  final List<RealtimeMeasurement> measurements;

  RealtimeMeasurements({
    required this.timestamp,
    required this.measurements,
  });

  factory RealtimeMeasurements.fromJson(Map<String, dynamic> json) {
    final measurementsJson = json['measurements'] as List<dynamic>;
    final measurements = measurementsJson
        .map((m) => RealtimeMeasurement.fromJson(m as Map<String, dynamic>))
        .toList();
    
    return RealtimeMeasurements(
      timestamp: DateTime.parse(json['timestamp'] as String).toUtc(),
      measurements: measurements,
    );
  }
}

// ============================================================================
// Dashboard/Statistics Models
// ============================================================================

class PrecipitationStats {
  final double maxValue;
  final double avgValue;
  final double medianValue;
  final String sensorName;
  final String sensorId;
  final DateTime timestamp;
  final int activeSensorCount;

  PrecipitationStats({
    required this.maxValue,
    required this.avgValue,
    required this.medianValue,
    required this.sensorName,
    required this.sensorId,
    required this.timestamp,
    required this.activeSensorCount,
  });
}

class TimeSeriesData {
  final DateTime timestamp;
  final double value;

  TimeSeriesData({
    required this.timestamp,
    required this.value,
  });
}

class SensorStats {
  final String sensorId;
  final String sensorName;
  final double totalPrecipitation;
  final double avgRate;
  final double peakIntensity;
  final int dataPointCount;
  final int rainyPeriodCount;
  final int dryPeriodCount;
  final List<TimeSeriesData> timeseries;
  final List<TimeSeriesData> trends;

  SensorStats({
    required this.sensorId,
    required this.sensorName,
    required this.totalPrecipitation,
    required this.avgRate,
    required this.peakIntensity,
    required this.dataPointCount,
    required this.rainyPeriodCount,
    required this.dryPeriodCount,
    required this.timeseries,
    required this.trends,
  });
}
