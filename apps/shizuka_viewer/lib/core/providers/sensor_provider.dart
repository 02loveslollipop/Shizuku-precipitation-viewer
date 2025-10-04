/// Sensor Provider
/// 
/// Manages sensor data state and API interactions.

import 'package:flutter/foundation.dart';
import '../api/api_v1_client.dart';
import '../api/api_models.dart';

class SensorProvider with ChangeNotifier {
  final ApiV1Client apiClient;
  
  List<Sensor> _sensors = [];
  bool _isLoading = false;
  String? _error;
  
  // Pagination
  int _currentPage = 1;
  int _totalPages = 1;
  int _limit = 50;
  
  // Selected sensor details
  Sensor? _selectedSensor;
  SensorMeasurements? _selectedSensorMeasurements;
  bool _loadingSensorDetails = false;

  SensorProvider({required this.apiClient});

  // Getters
  List<Sensor> get sensors => _sensors;
  bool get isLoading => _isLoading;
  String? get error => _error;
  int get currentPage => _currentPage;
  int get totalPages => _totalPages;
  bool get hasMore => _currentPage < _totalPages;
  
  Sensor? get selectedSensor => _selectedSensor;
  SensorMeasurements? get selectedSensorMeasurements => _selectedSensorMeasurements;
  bool get loadingSensorDetails => _loadingSensorDetails;

  /// Load sensors for a specific page
  Future<void> loadSensors({int page = 1, int limit = 50}) async {
    _isLoading = true;
    _error = null;
    _limit = limit;
    notifyListeners();
    
    try {
      final response = await apiClient.getSensors(
        page: page,
        limit: limit,
      );
      
      _sensors = response.data;
      _currentPage = response.pagination.page;
      _totalPages = response.pagination.totalPages;
      _error = null;
    } on ApiException catch (e) {
      _error = e.message;
      _sensors = [];
    } catch (e) {
      _error = 'Unexpected error: $e';
      _sensors = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Load next page of sensors (append to current list)
  Future<void> loadNextPage() async {
    if (!hasMore || _isLoading) return;
    
    _isLoading = true;
    notifyListeners();
    
    try {
      final response = await apiClient.getSensors(
        page: _currentPage + 1,
        limit: _limit,
      );
      
      _sensors.addAll(response.data);
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

  /// Refresh sensors (reload first page)
  Future<void> refresh() async {
    await loadSensors(page: 1, limit: _limit);
  }

  /// Load specific sensor details
  Future<void> loadSensorDetails(String sensorId) async {
    _loadingSensorDetails = true;
    _selectedSensor = null;
    _selectedSensorMeasurements = null;
    notifyListeners();
    
    try {
      _selectedSensor = await apiClient.getSensor(sensorId);
      _error = null;
    } on ApiException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = 'Unexpected error: $e';
    } finally {
      _loadingSensorDetails = false;
      notifyListeners();
    }
  }

  /// Load measurements for a sensor
  Future<void> loadSensorMeasurements(
    String sensorId, {
    bool clean = true,
    DateTime? start,
    DateTime? end,
    int limit = 200,
  }) async {
    _loadingSensorDetails = true;
    notifyListeners();
    
    try {
      _selectedSensorMeasurements = await apiClient.getSensorMeasurements(
        sensorId,
        clean: clean,
        start: start,
        end: end,
        limit: limit,
      );
      _error = null;
    } on ApiException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = 'Unexpected error: $e';
    } finally {
      _loadingSensorDetails = false;
      notifyListeners();
    }
  }

  /// Find sensor by ID in the current list
  Sensor? findSensorById(String id) {
    try {
      return _sensors.firstWhere((sensor) => sensor.id == id);
    } catch (e) {
      return null;
    }
  }

  /// Clear selected sensor
  void clearSelection() {
    _selectedSensor = null;
    _selectedSensorMeasurements = null;
    notifyListeners();
  }

  /// Clear all data
  void clear() {
    _sensors = [];
    _selectedSensor = null;
    _selectedSensorMeasurements = null;
    _currentPage = 1;
    _totalPages = 1;
    _error = null;
    notifyListeners();
  }
}
