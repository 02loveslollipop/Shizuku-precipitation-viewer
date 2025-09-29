import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
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
  final MapController _mapController = MapController();

  bool _isLoading = true;
  String? _errorMessage;

  List<SensorMeasurement> _measurements = [];
  List<SeriesPoint> _series = [];
  int _selectedIndex = 0;
  VisualizationMode _mode = VisualizationMode.heatmap;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final results = await Future.wait([
        _apiClient.fetchLatestMeasurements(),
        _apiClient.fetchAverageSeries(hoursBack: 24),
      ]);

      final sensors = results[0] as List<SensorMeasurement>;
      final series = results[1] as List<SeriesPoint>;

      if (!mounted) return;

      setState(() {
        _measurements = sensors;
        _series = series.isEmpty
            ? [
                SeriesPoint(
                  timestamp: sensors.isNotEmpty
                      ? sensors.first.timestamp
                      : DateTime.now().toUtc(),
                  value: sensors.isNotEmpty
                      ? sensors.map((s) => s.valueMm).reduce((a, b) => a + b) / sensors.length
                      : 0,
                ),
              ]
            : series;
        if (_selectedIndex >= _series.length) {
          _selectedIndex = _series.length - 1;
        }
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Failed to load data. $e';
        _isLoading = false;
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
            SvgPicture.asset(
              'assets/icons/shizuku_logo.svg',
              height: 32,
            ),
            const SizedBox(width: 12),
            Text(
              'Shizuku',
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          Builder(
            builder: (context) => IconButton(
              icon: const Icon(Icons.menu),
              onPressed: () => Scaffold.of(context).openEndDrawer(),
            ),
          )
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? _buildError(theme)
              : Column(
                  children: [
                    Expanded(
                      flex: 7,
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
                      flex: 2,
                      child: PrecipitationPanel(
                        series: _series,
                        selectedIndex: _selectedIndex,
                        onIndexChanged: (index) {
                          setState(() {
                            _selectedIndex = index;
                          });
                        },
                      ),
                    ),
                  ],
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loadData,
        icon: const Icon(Icons.refresh),
        label: const Text('Refresh'),
      ),
    );
  }

  Widget _buildMap() {
    final center = _measurements.isNotEmpty
        ? LatLng(
            _measurements.map((m) => m.lat).reduce((a, b) => a + b) / _measurements.length,
            _measurements.map((m) => m.lon).reduce((a, b) => a + b) / _measurements.length,
          )
        : const LatLng(6.2442, -75.5812);

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: center,
        initialZoom: 11,
        interactionOptions: const InteractionOptions(flags: ~InteractiveFlag.rotate),
      ),
      children: [
        TileLayer(
          urlTemplate:
              'https://api.mapbox.com/styles/v1/mapbox/streets-v12/tiles/256/{z}/{x}/{y}@2x?access_token=$mapboxAccessToken',
          additionalOptions: const {
            'access_token': mapboxAccessToken,
          },
          userAgentPackageName: 'com.shizuku.viewer',
        ),
        MarkerLayer(markers: _buildMarkers()),
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
            builder: (context) => _SensorMarker(
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
      builder: (context) => SensorDetailSheet(
        measurement: measurement,
        history: history,
      ),
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
            )
          ],
        ),
      ),
    );
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
    final tooltip = '${measurement.name ?? measurement.sensorId}\n${measurement.valueMm.toStringAsFixed(2)} mm\n${cls.label}';

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
                BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
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
