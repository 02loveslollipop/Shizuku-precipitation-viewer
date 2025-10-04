/// Heatmap Widget - Shows grid data with heatmap and contours
/// 
/// Extends BaseMapWidget to show precipitation grid data

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/api/api_models.dart';
import 'base_map_widget.dart';

class HeatmapWidget extends BaseMapWidget {
  final GridTimestamp? gridData;
  final List<Sensor> sensors;
  final bool showSensors;
  final bool showHeatmap;
  final bool showContours;
  final Uint8List? heatmapImage;
  final List<Polyline>? contourLines;

  const HeatmapWidget({
    Key? key,
    required super.initialCenter,
    super.initialZoom,
    super.bounds,
    super.onSensorTap,
    super.minZoom,
    super.maxZoom,
    this.gridData,
    required this.sensors,
    this.showSensors = true,
    this.showHeatmap = true,
    this.showContours = true,
    this.heatmapImage,
    this.contourLines,
  }) : super(key: key);

  @override
  State<HeatmapWidget> createState() => _HeatmapWidgetState();
}

class _HeatmapWidgetState extends BaseMapState<HeatmapWidget> {
  @override
  List<Marker> buildMarkers() {
    if (!widget.showSensors) return [];

    return widget.sensors.map((sensor) {
      // Find sensor aggregate data if available
      SensorAggregate? sensorData;
      if (widget.gridData?.sensors != null) {
        try {
          sensorData = widget.gridData!.sensors!.firstWhere(
            (s) => s.sensorId == sensor.id,
          );
        } catch (e) {
          // Sensor not found in aggregates
        }
      }

      return Marker(
        point: LatLng(sensor.lat, sensor.lon),
        width: 80,
        height: 80,
        child: GestureDetector(
          onTap: () => widget.onSensorTap?.call(sensor.id),
          child: _SensorMarker(
            sensor: sensor,
            sensorData: sensorData,
          ),
        ),
      );
    }).toList();
  }

  @override
  List<Widget> buildOverlayLayers() {
    final layers = <Widget>[];

    // Heatmap layer
    if (widget.showHeatmap && widget.heatmapImage != null && widget.bounds != null) {
      layers.add(
        OverlayImageLayer(
          overlayImages: [
            OverlayImage(
              bounds: widget.bounds!,
              opacity: 0.6,
              imageProvider: MemoryImage(widget.heatmapImage!),
            ),
          ],
        ),
      );
    }

    // Contour lines
    if (widget.showContours && widget.contourLines != null) {
      layers.add(
        PolylineLayer(polylines: widget.contourLines!),
      );
    }

    return layers;
  }

  @override
  Widget? buildMapOverlay() {
    if (widget.gridData == null) return null;

    return Positioned(
      top: 16,
      right: 16,
      child: Card(
        elevation: 4,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.access_time, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    _formatTimestamp(widget.gridData!.ts),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              if (widget.gridData!.sensors != null) ...[
                const SizedBox(height: 4),
                Text(
                  '${widget.gridData!.sensors!.length} sensors',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _formatTimestamp(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

class _SensorMarker extends StatelessWidget {
  final Sensor sensor;
  final SensorAggregate? sensorData;

  const _SensorMarker({
    Key? key,
    required this.sensor,
    this.sensorData,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final color = sensorData != null 
        ? _getIntensityColor(sensorData!.avgMmH)
        : Colors.grey;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(6),
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
            Icons.location_on,
            color: Colors.white,
            size: 16,
          ),
        ),
        if (sensorData != null)
          Container(
            margin: const EdgeInsets.only(top: 2),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(3),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 2,
                ),
              ],
            ),
            child: Text(
              '${sensorData!.avgMmH.toStringAsFixed(1)}',
              style: const TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
      ],
    );
  }

  Color _getIntensityColor(double mmH) {
    // Color mapping based on precipitation intensity (mm/h)
    if (mmH >= 50) return Colors.red[900]!;      // Extreme
    if (mmH >= 20) return Colors.red[600]!;      // Very heavy
    if (mmH >= 10) return Colors.orange[700]!;   // Heavy
    if (mmH >= 5) return Colors.orange[400]!;    // Moderate
    if (mmH >= 2) return Colors.yellow[700]!;    // Light
    if (mmH >= 0.5) return Colors.lightBlue;     // Very light
    return Colors.grey;                          // Trace/none
  }
}
