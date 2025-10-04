/// API v1 Client
/// 
/// HTTP client for new /api/v1 endpoints with error handling,
/// retry logic, and response caching.

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_models.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final String? responseBody;

  ApiException(this.message, {this.statusCode, this.responseBody});

  @override
  String toString() {
    if (statusCode != null) {
      return 'ApiException: $message (Status: $statusCode)';
    }
    return 'ApiException: $message';
  }
}

class ApiV1Client {
  final String baseUrl;
  final Duration timeout;
  final int maxRetries;
  
  // Simple in-memory cache
  final Map<String, _CacheEntry> _cache = {};
  final Duration _cacheDuration = const Duration(minutes: 5);

  ApiV1Client({
    required this.baseUrl,
    this.timeout = const Duration(seconds: 30),
    this.maxRetries = 3,
  });

  // ============================================================================
  // Core Endpoints
  // ============================================================================

  /// Get paginated list of sensors
  Future<PaginatedSensors> getSensors({
    int page = 1,
    int limit = 50,
  }) async {
    final params = {
      'page': page.toString(),
      'limit': limit.toString(),
    };
    
    final response = await _get('/api/v1/core/sensors', params: params);
    return PaginatedSensors.fromJson(response);
  }

  /// Get specific sensor details
  Future<Sensor> getSensor(String id) async {
    final response = await _get('/api/v1/core/sensors/$id');
    return Sensor.fromJson(response);
  }

  /// Get sensor measurements with filters
  Future<SensorMeasurements> getSensorMeasurements(
    String id, {
    bool clean = true,
    DateTime? start,
    DateTime? end,
    int limit = 200,
  }) async {
    final params = <String, String>{
      'clean': clean.toString(),
      'limit': limit.toString(),
    };
    
    if (start != null) {
      params['start'] = start.toIso8601String();
    }
    if (end != null) {
      params['end'] = end.toIso8601String();
    }
    
    final response = await _get(
      '/api/v1/core/sensors/$id/measurements',
      params: params,
    );
    return SensorMeasurements.fromJson(response);
  }

  // ============================================================================
  // Grid Endpoints
  // ============================================================================

  /// Get paginated grid timestamps with optional sensor aggregates
  Future<PaginatedGridTimestamps> getGridTimestamps({
    int page = 1,
    int limit = 20,
    DateTime? start,
    DateTime? end,
    bool includeSensors = true,
  }) async {
    final params = <String, String>{
      'page': page.toString(),
      'limit': limit.toString(),
      'include_sensors': includeSensors.toString(),
    };
    
    if (start != null) {
      params['start'] = start.toIso8601String();
    }
    if (end != null) {
      params['end'] = end.toIso8601String();
    }
    
    final response = await _get('/api/v1/grid/timestamps', params: params);
    return PaginatedGridTimestamps.fromJson(response);
  }

  /// Get specific grid timestamp details
  Future<GridTimestamp> getGridTimestamp(
    DateTime ts, {
    bool includeSensors = true,
  }) async {
    final timestamp = ts.toIso8601String();
    final params = {
      'include_sensors': includeSensors.toString(),
    };
    
    final response = await _get(
      '/api/v1/grid/timestamps/$timestamp',
      params: params,
    );
    return GridTimestamp.fromJson(response);
  }

  /// Get latest grid information
  Future<LatestGrid> getLatestGrid() async {
    final response = await _get('/api/v1/grid/latest');
    return LatestGrid.fromJson(response);
  }

  // ============================================================================
  // Real-time Endpoints
  // ============================================================================

  /// Get current real-time measurements for all sensors
  Future<RealtimeMeasurements> getRealtimeNow() async {
    // Don't cache real-time data
    final response = await _get('/api/v1/realtime/now', useCache: false);
    return RealtimeMeasurements.fromJson(response);
  }

  // ============================================================================
  // HTTP Methods
  // ============================================================================

  Future<Map<String, dynamic>> _get(
    String path, {
    Map<String, String>? params,
    bool useCache = true,
  }) async {
    final uri = _buildUri(path, params);
    final cacheKey = uri.toString();
    
    // Check cache
    if (useCache && _cache.containsKey(cacheKey)) {
      final entry = _cache[cacheKey]!;
      if (DateTime.now().difference(entry.timestamp) < _cacheDuration) {
        return entry.data;
      } else {
        _cache.remove(cacheKey);
      }
    }
    
    // Retry logic
    int attempts = 0;
    Exception? lastException;
    
    while (attempts < maxRetries) {
      try {
        final response = await http.get(uri).timeout(timeout);
        
        if (response.statusCode == 200) {
          final data = json.decode(response.body) as Map<String, dynamic>;
          
          // Cache successful response
          if (useCache) {
            _cache[cacheKey] = _CacheEntry(
              data: data,
              timestamp: DateTime.now(),
            );
          }
          
          return data;
        } else if (response.statusCode >= 400 && response.statusCode < 500) {
          // Client errors shouldn't be retried
          throw ApiException(
            'Client error: ${response.statusCode}',
            statusCode: response.statusCode,
            responseBody: response.body,
          );
        } else {
          // Server errors can be retried
          lastException = ApiException(
            'Server error: ${response.statusCode}',
            statusCode: response.statusCode,
            responseBody: response.body,
          );
        }
      } on http.ClientException catch (e) {
        lastException = ApiException('Network error: ${e.message}');
      } on FormatException catch (e) {
        throw ApiException('Invalid JSON response: ${e.message}');
      } catch (e) {
        lastException = ApiException('Unexpected error: $e');
      }
      
      attempts++;
      if (attempts < maxRetries) {
        // Exponential backoff
        await Future.delayed(Duration(milliseconds: 500 * attempts));
      }
    }
    
    throw lastException ?? ApiException('Request failed after $maxRetries attempts');
  }

  Uri _buildUri(String path, Map<String, String>? params) {
    final uri = Uri.parse('$baseUrl$path');
    if (params != null && params.isNotEmpty) {
      return uri.replace(queryParameters: params);
    }
    return uri;
  }

  /// Clear the response cache
  void clearCache() {
    _cache.clear();
  }

  /// Get cache statistics (for debugging)
  Map<String, dynamic> getCacheStats() {
    final now = DateTime.now();
    int validEntries = 0;
    int expiredEntries = 0;
    
    for (final entry in _cache.values) {
      if (now.difference(entry.timestamp) < _cacheDuration) {
        validEntries++;
      } else {
        expiredEntries++;
      }
    }
    
    return {
      'total_entries': _cache.length,
      'valid_entries': validEntries,
      'expired_entries': expiredEntries,
      'cache_duration_minutes': _cacheDuration.inMinutes,
    };
  }
}

class _CacheEntry {
  final Map<String, dynamic> data;
  final DateTime timestamp;

  _CacheEntry({
    required this.data,
    required this.timestamp,
  });
}
