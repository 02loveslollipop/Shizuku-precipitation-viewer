/// Base Map Widget - Abstract class for map implementations
/// 
/// Provides common map functionality that can be extended by
/// specific visualization types (heatmap, realtime, etc.)

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Base map widget providing common map functionality
abstract class BaseMapWidget extends StatefulWidget {
  final LatLng initialCenter;
  final double initialZoom;
  final LatLngBounds? bounds;
  final Function(String sensorId)? onSensorTap;
  final double? minZoom;
  final double? maxZoom;

  const BaseMapWidget({
    Key? key,
    required this.initialCenter,
    this.initialZoom = 11.0,
    this.bounds,
    this.onSensorTap,
    this.minZoom = 8.0,
    this.maxZoom = 16.0,
  }) : super(key: key);
}

/// Base state for map widgets
abstract class BaseMapState<T extends BaseMapWidget> extends State<T> {
  late MapController mapController;

  @override
  void initState() {
    super.initState();
    mapController = MapController();
  }

  @override
  void dispose() {
    mapController.dispose();
    super.dispose();
  }

  // Abstract methods to be implemented by subclasses
  
  /// Build marker layers for the map
  List<Marker> buildMarkers();
  
  /// Build overlay layers (heatmap, contours, etc.)
  List<Widget> buildOverlayLayers();
  
  /// Optional: Build additional UI overlays
  Widget? buildMapOverlay() => null;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        FlutterMap(
          mapController: mapController,
          options: MapOptions(
            initialCenter: widget.initialCenter,
            initialZoom: widget.initialZoom,
            minZoom: widget.minZoom,
            maxZoom: widget.maxZoom,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all,
            ),
          ),
          children: [
            // Base tile layer
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.siata.shizuku_viewer',
              maxZoom: 19,
            ),
            // Overlay layers (heatmap, contours, etc.)
            ...buildOverlayLayers(),
            // Marker layer
            MarkerLayer(markers: buildMarkers()),
          ],
        ),
        // Optional UI overlay
        if (buildMapOverlay() != null) buildMapOverlay()!,
      ],
    );
  }

  /// Helper: Move map to specific location
  void moveToLocation(LatLng location, {double? zoom}) {
    mapController.move(location, zoom ?? mapController.camera.zoom);
  }

  /// Helper: Fit map to bounds
  void fitBounds(LatLngBounds bounds, {EdgeInsets padding = const EdgeInsets.all(20)}) {
    mapController.fitCamera(
      CameraFit.bounds(
        bounds: bounds,
        padding: padding,
      ),
    );
  }

  /// Helper: Get current zoom level
  double get currentZoom => mapController.camera.zoom;

  /// Helper: Get current center
  LatLng get currentCenter => mapController.camera.center;
}
