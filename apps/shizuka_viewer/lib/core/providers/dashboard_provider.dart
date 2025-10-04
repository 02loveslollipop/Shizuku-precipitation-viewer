/// Dashboard Provider
/// 
/// Manages dashboard statistics and analytics state

import 'package:flutter/foundation.dart';
import '../api/api_v1_client.dart';
import '../api/api_models.dart';

enum TimePeriod {
  hour1('1 Hour', Duration(hours: 1)),
  hours6('6 Hours', Duration(hours: 6)),
  hours24('24 Hours', Duration(hours: 24)),
  hours48('48 Hours', Duration(hours: 48)),
  days7('7 Days', Duration(days: 7)),
  month1('1 Month', Duration(days: 30));

  const TimePeriod(this.label, this.duration);
  final String label;
  final Duration duration;
}

class DashboardProvider with ChangeNotifier {
  final ApiV1Client apiClient;

  bool _isLoading = false;
  String? _error;

  // Sensors
  List<Sensor> _sensors = [];
  
  // Max precipitation stats
  PrecipitationStats? _maxStats;
  PrecipitationStats? _totalStats;

  // Selected sensor stats
  String? _selectedSensorId;
  SensorStats? _selectedSensorStats;
  bool _loadingSensorStats = false;

  DashboardProvider({required this.apiClient});

  // Getters
  bool get isLoading => _isLoading;
  String? get error => _error;
  List<Sensor> get sensors => _sensors;
  PrecipitationStats? get maxStats => _maxStats;
  PrecipitationStats? get totalStats => _totalStats;
  String? get selectedSensorId => _selectedSensorId;
  SensorStats? get selectedSensorStats => _selectedSensorStats;
  bool get loadingSensorStats => _loadingSensorStats;

  /// Load all sensors for the selector
  Future<void> loadSensors() async {
    _isLoading = true;
    notifyListeners();

    try {
      final response = await apiClient.getSensors(page: 1, limit: 100);
      _sensors = response.data;
      _error = null;
    } on ApiException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = 'Unexpected error: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Load statistics for a time period
  Future<void> loadStats({required TimePeriod period}) async {
    _isLoading = true;
    notifyListeners();

    try {
      final end = DateTime.now().toUtc();
      final start = end.subtract(period.duration);

      // Load grid timestamps with sensor data
      final response = await apiClient.getGridTimestamps(
        page: 1,
        limit: 100,
        start: start,
        end: end,
        includeSensors: true,
      );

      // Calculate max precipitation stats
      _calculateMaxStats(response.data);
      _error = null;
    } on ApiException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = 'Unexpected error: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Load statistics for a specific sensor
  Future<void> loadSensorStats(String sensorId, TimePeriod period) async {
    _selectedSensorId = sensorId;
    _loadingSensorStats = true;
    notifyListeners();

    try {
      final end = DateTime.now().toUtc();
      final start = end.subtract(period.duration);

      // Load sensor measurements
      final measurements = await apiClient.getSensorMeasurements(
        sensorId,
        clean: true,
        start: start,
        end: end,
        limit: 1000,
      );

      // Calculate sensor statistics
      _selectedSensorStats = _calculateSensorStats(
        sensorId,
        measurements.measurements,
      );
      _error = null;
    } on ApiException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = 'Unexpected error: $e';
    } finally {
      _loadingSensorStats = false;
      notifyListeners();
    }
  }

  void _calculateMaxStats(List<GridTimestamp> gridData) {
    if (gridData.isEmpty) {
      _maxStats = null;
      _totalStats = null;
      return;
    }

    double maxValue = 0;
    String maxSensorId = '';
    String maxSensorName = '';
    DateTime maxTimestamp = DateTime.now().toUtc();
    
    int totalSensors = 0;
    Map<String, double> sensorTotals = {};

    // Find max and calculate totals
    for (final grid in gridData) {
      if (grid.sensors == null) continue;

      for (final sensorData in grid.sensors!) {
        // Track max
        if (sensorData.avgMmH > maxValue) {
          maxValue = sensorData.avgMmH;
          maxSensorId = sensorData.sensorId;
          maxTimestamp = grid.ts;
        }

        // Track totals
        sensorTotals[sensorData.sensorId] = 
            (sensorTotals[sensorData.sensorId] ?? 0) + sensorData.avgMmH;
      }

      totalSensors = grid.sensors!.length;
    }

    // Get sensor name for max
    try {
      final sensor = _sensors.firstWhere((s) => s.id == maxSensorId);
      maxSensorName = sensor.name;
    } catch (e) {
      maxSensorName = maxSensorId;
    }

    // Calculate averages
    final avgValue = sensorTotals.values.isEmpty 
        ? 0.0 
        : sensorTotals.values.reduce((a, b) => a + b) / sensorTotals.length;
    
    final medianValue = _calculateMedian(sensorTotals.values.toList());

    _maxStats = PrecipitationStats(
      maxValue: maxValue,
      avgValue: avgValue,
      medianValue: medianValue,
      sensorName: maxSensorName,
      sensorId: maxSensorId,
      timestamp: maxTimestamp,
      activeSensorCount: totalSensors,
    );

    // Find sensor with highest total
    if (sensorTotals.isNotEmpty) {
      final maxTotalEntry = sensorTotals.entries.reduce(
        (a, b) => a.value > b.value ? a : b,
      );

      String totalSensorName = maxTotalEntry.key;
      try {
        final sensor = _sensors.firstWhere((s) => s.id == maxTotalEntry.key);
        totalSensorName = sensor.name;
      } catch (e) {
        // Use ID if name not found
      }

      _totalStats = PrecipitationStats(
        maxValue: maxTotalEntry.value,
        avgValue: avgValue,
        medianValue: medianValue,
        sensorName: totalSensorName,
        sensorId: maxTotalEntry.key,
        timestamp: gridData.last.ts,
        activeSensorCount: totalSensors,
      );
    }
  }

  SensorStats _calculateSensorStats(
    String sensorId,
    List<Measurement> measurements,
  ) {
    if (measurements.isEmpty) {
      return SensorStats(
        sensorId: sensorId,
        sensorName: _getSensorName(sensorId),
        totalPrecipitation: 0,
        avgRate: 0,
        peakIntensity: 0,
        dataPointCount: 0,
        rainyPeriodCount: 0,
        dryPeriodCount: 0,
        timeseries: [],
        trends: [],
      );
    }

    // Calculate statistics
    final total = measurements.fold<double>(
      0, (sum, m) => sum + m.valueMm,
    );
    final avg = total / measurements.length;
    final peak = measurements.map((m) => m.valueMm).reduce((a, b) => a > b ? a : b);

    // Count rainy/dry periods (threshold: 0.1mm)
    int rainy = 0;
    int dry = 0;
    for (final m in measurements) {
      if (m.valueMm >= 0.1) {
        rainy++;
      } else {
        dry++;
      }
    }

    // Build time series
    final timeseries = measurements.map((m) => TimeSeriesData(
      timestamp: m.ts,
      value: m.valueMm,
    )).toList();

    // Build trends (moving average)
    final trends = _calculateMovingAverage(timeseries, windowSize: 5);

    return SensorStats(
      sensorId: sensorId,
      sensorName: _getSensorName(sensorId),
      totalPrecipitation: total,
      avgRate: avg,
      peakIntensity: peak,
      dataPointCount: measurements.length,
      rainyPeriodCount: rainy,
      dryPeriodCount: dry,
      timeseries: timeseries,
      trends: trends,
    );
  }

  List<TimeSeriesData> _calculateMovingAverage(
    List<TimeSeriesData> data, {
    int windowSize = 5,
  }) {
    if (data.length < windowSize) return data;

    final result = <TimeSeriesData>[];
    for (int i = 0; i < data.length; i++) {
      final start = (i - windowSize ~/ 2).clamp(0, data.length - windowSize);
      final end = start + windowSize;
      final window = data.sublist(start, end);
      final avg = window.fold<double>(0, (sum, d) => sum + d.value) / window.length;
      
      result.add(TimeSeriesData(
        timestamp: data[i].timestamp,
        value: avg,
      ));
    }
    return result;
  }

  double _calculateMedian(List<double> values) {
    if (values.isEmpty) return 0;
    
    final sorted = List<double>.from(values)..sort();
    final mid = sorted.length ~/ 2;
    
    if (sorted.length % 2 == 0) {
      return (sorted[mid - 1] + sorted[mid]) / 2;
    } else {
      return sorted[mid];
    }
  }

  String _getSensorName(String sensorId) {
    try {
      final sensor = _sensors.firstWhere((s) => s.id == sensorId);
      return sensor.name;
    } catch (e) {
      return sensorId;
    }
  }

  void clearSelection() {
    _selectedSensorId = null;
    _selectedSensorStats = null;
    notifyListeners();
  }

  void clear() {
    _sensors = [];
    _maxStats = null;
    _totalStats = null;
    _selectedSensorId = null;
    _selectedSensorStats = null;
    _error = null;
    notifyListeners();
  }
}
