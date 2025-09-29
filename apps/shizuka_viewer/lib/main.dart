import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'api/api_client.dart';
import 'app_constants.dart';
import 'app_theme.dart';
import 'widgets/precipitation_panel.dart';
import 'widgets/sensor_detail_sheet.dart';
import 'widgets/visualization_drawer.dart';

void main() {
  Intl.defaultLocale = 'en_US';
  runApp(const ShizukuViewerApp());
}

class ShizukuViewerApp extends StatelessWidget {
  const ShizukuViewerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Shizuku Viewer',
      theme: buildShizukuTheme(),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final ApiClient _apiClient = ApiClient();
  MapController? _mapController;
  bool _mapStyleLoaded = false;

  bool _isLoading = true;
  bool _isGridLoading = false;
  String? _errorMessage;

  List<SensorMeasurement> _measurements = [];
  List<SeriesPoint> _series = [];
  int _selectedIndex = 0;
  DateTime? _selectedTimestamp;
  VisualizationMode _mode = VisualizationMode.heatmap;
  Uint8List? _heatmapImage;
  LatLngBounds? _gridBounds;
  List<Polyline> _contourPolylines = [];
  DateTime? _gridTimestamp;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _isGridLoading = true;
      _errorMessage = null;
    });

    try {
      final measurementsFuture = _apiClient.fetchLatestMeasurements();
      final seriesFuture = _apiClient.fetchAverageSeries(hoursBack: 24);
      final gridFuture = _apiClient.fetchLatestGrid();

      final sensors = await measurementsFuture;
      final series = await seriesFuture;
      final gridSnapshot = await gridFuture;

      _GridOverlayAssets? overlay;
      if (gridSnapshot != null) {
        overlay = await _buildGridOverlay(gridSnapshot);
      }

      if (!mounted) return;

      setState(() {
        _measurements = sensors;
        _series =
            series.isEmpty
                ? [
                  SeriesPoint(
                    timestamp:
                        sensors.isNotEmpty
                            ? sensors.first.timestamp
                            : DateTime.now().toUtc(),
                    value:
                        sensors.isNotEmpty
                            ? sensors
                                    .map((s) => s.valueMm)
                                    .reduce((a, b) => a + b) /
                                sensors.length
                            : 0,
                  ),
                ]
                : series;
        if (_series.isNotEmpty) {
          if (_selectedIndex >= _series.length) {
            _selectedIndex = _series.length - 1;
          }
          _selectedTimestamp = _series[_selectedIndex].timestamp;
        } else {
          _selectedTimestamp = null;
        }
        if (gridSnapshot != null && overlay != null) {
          _heatmapImage = overlay.heatmapPng;
          _gridBounds = overlay.bounds;
          _contourPolylines = overlay.contours;
          _gridTimestamp = gridSnapshot.timestamp;
        } else {
          _heatmapImage = null;
          _gridBounds = null;
          _contourPolylines = [];
          _gridTimestamp = null;
        }
        _isLoading = false;
        _isGridLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Failed to load data. $e';
        _isLoading = false;
        _isGridLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _apiClient.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      endDrawer: VisualizationDrawer(
        mode: _mode,
        onModeChanged: (mode) {
          setState(() {
            _mode = mode;
          });
        },
      ),
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            SvgPicture.asset('assets/icons/shizuku_logo.svg', height: 32),
            const SizedBox(width: 12),
            Text(
              'Shizuku',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: 'Refresh data',
          ),
          Builder(
            builder:
                (context) => IconButton(
                  icon: const Icon(Icons.menu),
                  onPressed: () => Scaffold.of(context).openEndDrawer(),
                ),
          ),
        ],
      ),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _errorMessage != null
              ? _buildError(theme)
              : Column(
                children: [
                  Expanded(
                    flex: 8,
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.06),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: _buildMap(),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 1,
                    child: PrecipitationPanel(
                      series: _series,
                      selectedIndex: _selectedIndex,
                      onIndexChanged: _handleSeriesIndexChanged,
                    ),
                  ),
                ],
              ),
    );
  }

  Widget _buildMap() {
    final center =
        _measurements.isNotEmpty
            ? LatLng(
              _measurements.map((m) => m.lat).reduce((a, b) => a + b) /
                  _measurements.length,
              _measurements.map((m) => m.lon).reduce((a, b) => a + b) /
                  _measurements.length,
            )
            : const LatLng(6.2442, -75.5812);

    final children = <Widget>[
      TileLayer(
        urlTemplate:
            'https://basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png',
        userAgentPackageName: 'com.shizuku.viewer',
        tileProvider: NetworkTileProvider(),
        maxZoom: 19,
        minZoom: 2,
      ),
      if (_mode == VisualizationMode.heatmap &&
          _heatmapImage != null &&
          _gridBounds != null)
        OverlayImageLayer(
          overlayImages: [
            OverlayImage(
              bounds: _gridBounds!,
              opacity: 0.75,
              imageProvider: MemoryImage(_heatmapImage!),
            ),
          ],
        ),
      if (_mode == VisualizationMode.contour && _contourPolylines.isNotEmpty)
        PolylineLayer(polylines: _contourPolylines),
      MarkerLayer(markers: _buildMarkers()),
    ];

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: center,
            initialZoom: 11,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
            ),
          ),
          children: children,
        ),
        if (_isGridLoading)
          const Positioned.fill(
            child: IgnorePointer(
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
        if (_gridTimestamp != null)
          Positioned(
            top: 16,
            left: 16,
            child: _MapTimestampChip(
              timestamp: _selectedTimestamp ?? _gridTimestamp!,
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

  List<Marker> _buildMarkers() {
    return _measurements
        .map(
          (measurement) => Marker(
            point: LatLng(measurement.lat, measurement.lon),
            width: 42,
            height: 42,
            child: _SensorMarker(
              measurement: measurement,
              mode: _mode,
              onTap: () => _showSensorDetails(measurement),
            ),
          ),
        )
        .toList();
  }

  Future<void> _showSensorDetails(SensorMeasurement measurement) async {
    final history = await _apiClient.fetchSensorHistory(measurement.sensorId);
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      builder:
          (context) =>
              SensorDetailSheet(measurement: measurement, history: history),
    );
  }

  Widget _buildError(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _errorMessage ?? 'Unknown error',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadData,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  void _handleSeriesIndexChanged(int index) {
    setState(() {
      _selectedIndex = index;
      if (index >= 0 && index < _series.length) {
        _selectedTimestamp = _series[index].timestamp;
      }
    });
  }

  Future<_GridOverlayAssets?> _buildGridOverlay(GridSnapshot snapshot) async {
    final rows = snapshot.data.length;
    if (rows == 0) {
      return null;
    }
    final cols = snapshot.data.first.length;
    if (cols == 0) {
      return null;
    }

    final pixels = Uint8List(rows * cols * 4);
    for (var y = 0; y < rows; y++) {
      final sourceRow = snapshot.data[rows - 1 - y];
      for (var x = 0; x < cols; x++) {
        final offset = (y * cols + x) * 4;
        final value = sourceRow[x];
        if (value.isNaN) {
          pixels[offset] = 0;
          pixels[offset + 1] = 0;
          pixels[offset + 2] = 0;
          pixels[offset + 3] = 0;
          continue;
        }
        final color = colorForMeasurement(value, VisualizationMode.heatmap);
        pixels[offset] = color.red;
        pixels[offset + 1] = color.green;
        pixels[offset + 2] = color.blue;
        pixels[offset + 3] = 200;
      }
    }

    final pngBytes = await _encodeHeatmap(pixels, cols, rows);
    final bounds = LatLngBounds(
      LatLng(snapshot.south, snapshot.west),
      LatLng(snapshot.north, snapshot.east),
    );

    final polylines =
        snapshot.contours
            .where((feature) => feature.coordinates.length >= 2)
            .map((feature) {
              final intensity = findIntensityClass(feature.thresholdMm);
              final color = colorForIntensityClass(
                intensity,
                VisualizationMode.contour,
              ).withOpacity(0.9);
              final points =
                  feature.coordinates
                      .map((pair) => LatLng(pair[1], pair[0]))
                      .toList();
              return Polyline(points: points, color: color, strokeWidth: 2.2);
            })
            .toList();

    return _GridOverlayAssets(
      heatmapPng: pngBytes,
      bounds: bounds,
      contours: polylines,
    );
  }

  Future<Uint8List> _encodeHeatmap(
    Uint8List pixels,
    int width,
    int height,
  ) async {
    final completer = Completer<Uint8List>();
    ui.decodeImageFromPixels(pixels, width, height, ui.PixelFormat.rgba8888, (
      image,
    ) async {
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        completer.complete(Uint8List(0));
        return;
      }
      completer.complete(byteData.buffer.asUint8List());
    });
    return completer.future;
  }
}

class _SensorMarker extends StatelessWidget {
  const _SensorMarker({
    required this.measurement,
    required this.mode,
    required this.onTap,
  });

  final SensorMeasurement measurement;
  final VisualizationMode mode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = colorForMeasurement(measurement.valueMm, mode);
    final cls = findIntensityClass(measurement.valueMm);
    final tooltip =
        '${measurement.name ?? measurement.sensorId}\n${measurement.valueMm.toStringAsFixed(2)} mm\n${cls.label}\nLat: ${measurement.lat.toStringAsFixed(4)}, Lon: ${measurement.lon.toStringAsFixed(4)}\nAddress: Pending Mapbox lookup';

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Tooltip(
          message: tooltip,
          decoration: BoxDecoration(
            color: shizukuPrimary.withOpacity(0.9),
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: const TextStyle(color: Colors.white),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withOpacity(0.85),
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 4,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Center(
              child: Text(
                measurement.valueMm.toStringAsFixed(1),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MapTimestampChip extends StatelessWidget {
  const _MapTimestampChip({required this.timestamp});

  final DateTime timestamp;

  @override
  Widget build(BuildContext context) {
    final formatted = DateFormat('MMM d, HH:mm').format(timestamp.toLocal());
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(
          'Map time: $formatted',
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: shizukuPrimary),
        ),
      ),
    );
  }
}

class _GridOverlayAssets {
  _GridOverlayAssets({
    required this.heatmapPng,
    required this.bounds,
    required this.contours,
  });

  final Uint8List heatmapPng;
  final LatLngBounds bounds;
  final List<Polyline> contours;
}
