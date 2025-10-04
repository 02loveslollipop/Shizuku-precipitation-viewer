/// Simple Heatmap Widget for Classic UI
/// 
/// Reads data from GridProvider and displays heatmap with overlays

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/providers/grid_provider.dart';
import '../../core/api/api_models.dart';
import '../../app_constants.dart';

typedef SensorTapCallback = void Function(Sensor sensor, Measurement measurement);

class HeatmapWidget extends StatelessWidget {
  const HeatmapWidget({
    super.key,
    required this.showPins,
    required this.showHeatmap,
    required this.showContours,
    required this.onSensorTap,
  });

  final bool showPins;
  final bool showHeatmap;
  final bool showContours;
  final SensorTapCallback onSensorTap;

  @override
  Widget build(BuildContext context) {
    return Consumer<GridProvider>(
      builder: (context, gridProvider, child) {
        return _HeatmapMap(
          gridData: gridProvider.currentGridData,
          measurements: gridProvider.measurements,
          showPins: showPins,
          showHeatmap: showHeatmap,
          showContours: showContours,
          isLoading: gridProvider.isLoading,
          onSensorTap: onSensorTap,
        );
      },
    );
  }
}

class _HeatmapMap extends StatelessWidget {
  const _HeatmapMap({
    required this.gridData,
    required this.measurements,
    required this.showPins,
    required this.showHeatmap,
    required this.showContours,
    required this.isLoading,
    required this.onSensorTap,
  });

  final GridData? gridData;
  final List<SensorMeasurementData> measurements;
  final bool showPins;
  final bool showHeatmap;
  final bool showContours;
  final bool isLoading;
  final SensorTapCallback onSensorTap;

  @override
  Widget build(BuildContext context) {
    final center = _calculateCenter();

    return Stack(
      children: [
        FlutterMap(
          options: MapOptions(
            initialCenter: center,
            initialZoom: 11,
            minZoom: 8.0,
            maxZoom: 19.0,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
            ),
          ),
          children: [
            TileLayer(
              urlTemplate:
                  'https://basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.shizuku.viewer',
            ),
            // TODO: Add heatmap overlay when grid data is available
            // TODO: Add contour lines when available
            if (showPins) MarkerLayer(markers: _buildMarkers()),
          ],
        ),
        if (isLoading)
          Positioned.fill(
            child: Container(
              color: Colors.black.withOpacity(0.3),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 16),
                  Text(
                    'Loading data...',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        Positioned(
          bottom: 12,
          right: 12,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.55),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text(
                '© OpenStreetMap contributors · © CARTO',
                style: TextStyle(color: Colors.white, fontSize: 10),
              ),
            ),
          ),
        ),
      ],
    );
  }

  LatLng _calculateCenter() {
    if (measurements.isEmpty) {
      return const LatLng(6.2442, -75.5812); // Medellín default
    }
    
    final avgLat = measurements.map((m) => m.sensor.lat).reduce((a, b) => a + b) / measurements.length;
    final avgLon = measurements.map((m) => m.sensor.lon).reduce((a, b) => a + b) / measurements.length;
    return LatLng(avgLat, avgLon);
  }

  List<Marker> _buildMarkers() {
    return measurements.map((data) {
      return Marker(
        point: LatLng(data.sensor.lat, data.sensor.lon),
        width: 42,
        height: 42,
        child: GestureDetector(
          onTap: () => onSensorTap(data.sensor, data.measurement),
          child: _SensorPin(
            sensor: data.sensor,
            measurement: data.measurement,
          ),
        ),
      );
    }).toList();
  }
}

class _SensorPin extends StatelessWidget {
  const _SensorPin({
    required this.sensor,
    required this.measurement,
  });

  final Sensor sensor;
  final Measurement measurement;

  @override
  Widget build(BuildContext context) {
    final color = colorForPinMeasurement(measurement.valueMm);
    final severityKey = pinSeverityKey(measurement.valueMm);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: color,
          boxShadow: const [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 6,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              measurement.valueMm.toStringAsFixed(2),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              severityKey.split('.').last, // Extract "low", "moderate", "high"
              style: const TextStyle(
                color: Colors.white,
                fontSize: 8,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
