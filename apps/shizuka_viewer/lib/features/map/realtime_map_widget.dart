/// Real-time Map Widget - Shows current sensor measurements
/// 
/// Extends BaseMapWidget to show real-time precipitation data

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/api/api_models.dart';
import 'base_map_widget.dart';

class RealtimeMapWidget extends BaseMapWidget {
  final List<RealtimeMeasurement> measurements;
  final bool showLabels;
  final DateTime? timestamp;

  const RealtimeMapWidget({
    Key? key,
    required super.initialCenter,
    super.initialZoom,
    super.bounds,
    super.onSensorTap,
    super.minZoom,
    super.maxZoom,
    required this.measurements,
    this.showLabels = true,
    this.timestamp,
  }) : super(key: key);

  @override
  State<RealtimeMapWidget> createState() => _RealtimeMapWidgetState();
}

class _RealtimeMapWidgetState extends BaseMapState<RealtimeMapWidget> {
  @override
  List<Marker> buildMarkers() {
    return widget.measurements.map((measurement) {
      // Get sensor location from enriched data
      final sensor = measurement.sensor;
      if (sensor == null) return null;

      return Marker(
        point: LatLng(sensor.lat, sensor.lon),
        width: 80,
        height: 80,
        child: GestureDetector(
          onTap: () => widget.onSensorTap?.call(measurement.sensorId),
          child: _RealtimeMarker(
            measurement: measurement,
            showLabel: widget.showLabels,
          ),
        ),
      );
    }).whereType<Marker>().toList();
  }

  @override
  List<Widget> buildOverlayLayers() {
    // Real-time doesn't use overlays (no heatmap/contours)
    return [];
  }

  @override
  Widget? buildMapOverlay() {
    if (widget.measurements.isEmpty) return null;

    // Get the most recent measurement timestamp from actual data
    final latestTimestamp = widget.measurements
        .map((m) => m.ts)
        .reduce((a, b) => a.isAfter(b) ? a : b);

    return Positioned(
      top: 16,
      right: 16,
      child: Card(
        elevation: 4,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.access_time, size: 16, color: Colors.green),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Real-time',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                  Text(
                    _formatTimestamp(latestTimestamp),
                    style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTimestamp(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
  }
}

class _RealtimeMarker extends StatelessWidget {
  final RealtimeMeasurement measurement;
  final bool showLabel;

  const _RealtimeMarker({
    Key? key,
    required this.measurement,
    this.showLabel = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final color = _getIntensityColor(measurement.valueMm);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 4,
              ),
            ],
          ),
          child: const Icon(
            Icons.water_drop,
            color: Colors.white,
            size: 18,
          ),
        ),
        if (showLabel)
          Container(
            margin: const EdgeInsets.only(top: 2),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: color, width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 2,
                ),
              ],
            ),
            child: Text(
              '${measurement.valueMm.toStringAsFixed(2)} mm',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
      ],
    );
  }

  Color _getIntensityColor(double valueMm) {
    // Color mapping based on precipitation amount (mm)
    // Note: Real-time shows instantaneous readings, not rates
    if (valueMm >= 10) return Colors.red[900]!;      // Extreme
    if (valueMm >= 5) return Colors.red[600]!;       // Very heavy
    if (valueMm >= 2) return Colors.orange[700]!;    // Heavy
    if (valueMm >= 1) return Colors.orange[400]!;    // Moderate
    if (valueMm >= 0.5) return Colors.yellow[700]!;  // Light
    if (valueMm >= 0.1) return Colors.lightBlue;     // Very light
    return Colors.grey;                              // Trace/none
  }
}
