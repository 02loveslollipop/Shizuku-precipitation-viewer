/// Grid Provider
/// 
/// Manages grid data state, timeline, and real-time measurements.

import 'package:flutter/foundation.dart';
import '../api/api_v1_client.dart';
import '../api/api_models.dart';

/// Helper class to combine sensor and measurement data
class SensorMeasurementData {
  final Sensor sensor;
  final Measurement measurement;

  SensorMeasurementData({
    required this.sensor,
    required this.measurement,
  });
}

class GridProvider with ChangeNotifier {
  final ApiV1Client apiClient;
  
  List<GridTimestamp> _gridTimestamps = [];
  bool _isLoading = false;
  String? _error;
  
  // Pagination
  int _currentPage = 1;
  int _totalPages = 1;
  int _limit = 20;
  
  // Selected grid
  GridTimestamp? _selectedGrid;
  int _selectedIndex = 0;
  
  // Latest grid
  LatestGrid? _latestGrid;
  
  // Real-time measurements
  RealtimeMeasurements? _realtimeMeasurements;
  bool _loadingRealtime = false;

  GridProvider({required this.apiClient});

  // Getters
  List<GridTimestamp> get gridTimestamps => _gridTimestamps;
  bool get isLoading => _isLoading;
  String? get error => _error;
  int get currentPage => _currentPage;
  int get totalPages => _totalPages;
  bool get hasMore => _currentPage < _totalPages;
  
  GridTimestamp? get selectedGrid => _selectedGrid;
  int get selectedIndex => _selectedIndex;
  bool get hasSelection => _selectedGrid != null;
  
  LatestGrid? get latestGrid => _latestGrid;
  
  RealtimeMeasurements? get realtimeMeasurements => _realtimeMeasurements;
  bool get loadingRealtime => _loadingRealtime;
  
  /// Get measurements as a list of SensorMeasurementData for map display
  List<SensorMeasurementData> get measurements {
    if (_realtimeMeasurements == null) return [];
    
    return _realtimeMeasurements!.measurements
        .where((m) => m.sensor != null) // Only include measurements with sensor data
        .map((realtimeMeasurement) {
          // Convert RealtimeMeasurement to Measurement format
          final measurement = Measurement(
            ts: realtimeMeasurement.ts,
            sensorId: realtimeMeasurement.sensorId,
            valueMm: realtimeMeasurement.valueMm,
          );
          
          return SensorMeasurementData(
            sensor: realtimeMeasurement.sensor!,
            measurement: measurement,
          );
        })
        .toList();
  }

  /// Load grid timestamps
  Future<void> loadGridTimestamps({
    int page = 1,
    int limit = 20,
    DateTime? start,
    DateTime? end,
    bool includeSensors = true,
  }) async {
    _isLoading = true;
    _error = null;
    _limit = limit;
    notifyListeners();
    
    try {
      final response = await apiClient.getGridTimestamps(
        page: page,
        limit: limit,
        start: start,
        end: end,
        includeSensors: includeSensors,
      );
      
      _gridTimestamps = response.data;
      _currentPage = response.pagination.page;
      _totalPages = response.pagination.totalPages;
      
      // Auto-select first grid if none selected
      if (_gridTimestamps.isNotEmpty && _selectedGrid == null) {
        _selectedGrid = _gridTimestamps[0];
        _selectedIndex = 0;
      }
      
      _error = null;
    } on ApiException catch (e) {
      _error = e.message;
      _gridTimestamps = [];
    } catch (e) {
      _error = 'Unexpected error: $e';
      _gridTimestamps = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Load next page of grid timestamps (append to current list)
  Future<void> loadNextPage({
    DateTime? start,
    DateTime? end,
    bool includeSensors = true,
  }) async {
    if (!hasMore || _isLoading) return;
    
    _isLoading = true;
    notifyListeners();
    
    try {
      final response = await apiClient.getGridTimestamps(
        page: _currentPage + 1,
        limit: _limit,
        start: start,
        end: end,
        includeSensors: includeSensors,
      );
      
      _gridTimestamps.addAll(response.data);
      _currentPage = response.pagination.page;
      _totalPages = response.pagination.totalPages;
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

  /// Select a grid by index
  void selectGridByIndex(int index) {
    if (index >= 0 && index < _gridTimestamps.length) {
      _selectedIndex = index;
      _selectedGrid = _gridTimestamps[index];
      notifyListeners();
    }
  }

  /// Select a grid by timestamp
  void selectGridByTimestamp(DateTime ts) {
    final index = _gridTimestamps.indexWhere((grid) => grid.ts == ts);
    if (index != -1) {
      selectGridByIndex(index);
    }
  }

  /// Load specific grid timestamp details
  Future<void> loadGridDetails(
    DateTime ts, {
    bool includeSensors = true,
  }) async {
    _isLoading = true;
    notifyListeners();
    
    try {
      _selectedGrid = await apiClient.getGridTimestamp(
        ts,
        includeSensors: includeSensors,
      );
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

  /// Load latest grid
  Future<void> loadLatestGrid() async {
    _isLoading = true;
    notifyListeners();
    
    try {
      _latestGrid = await apiClient.getLatestGrid();
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

  /// Load real-time measurements
  Future<void> loadRealtimeMeasurements() async {
    _loadingRealtime = true;
    notifyListeners();
    
    try {
      _realtimeMeasurements = await apiClient.getRealtimeNow();
      _error = null;
    } on ApiException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = 'Unexpected error: $e';
    } finally {
      _loadingRealtime = false;
      notifyListeners();
    }
  }

  /// Navigate to next grid in timeline
  void nextGrid() {
    if (_selectedIndex < _gridTimestamps.length - 1) {
      selectGridByIndex(_selectedIndex + 1);
    }
  }

  /// Navigate to previous grid in timeline
  void previousGrid() {
    if (_selectedIndex > 0) {
      selectGridByIndex(_selectedIndex - 1);
    }
  }

  /// Check if can navigate to next
  bool get canGoNext => _selectedIndex < _gridTimestamps.length - 1;

  /// Check if can navigate to previous
  bool get canGoPrevious => _selectedIndex > 0;

  /// Refresh grid data
  Future<void> refresh({
    DateTime? start,
    DateTime? end,
    bool includeSensors = true,
  }) async {
    await loadGridTimestamps(
      page: 1,
      limit: _limit,
      start: start,
      end: end,
      includeSensors: includeSensors,
    );
  }

  /// Clear selection
  void clearSelection() {
    _selectedGrid = null;
    _selectedIndex = 0;
    notifyListeners();
  }

  /// Clear all data
  void clear() {
    _gridTimestamps = [];
    _selectedGrid = null;
    _selectedIndex = 0;
    _latestGrid = null;
    _realtimeMeasurements = null;
    _currentPage = 1;
    _totalPages = 1;
    _error = null;
    notifyListeners();
  }
}
