import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';
import 'package:mapbox_gl/mapbox_gl.dart';

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
  MapboxMapController? _mapController;
  final List<Symbol> _symbols = [];
  final Map<String, SensorMeasurement> _symbolIdToSensor = {};

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

      if (mounted) {
        setState(() {
          _measurements = sensors;
          _series = series.isEmpty
              ? [
                  SeriesPoint(
                    timestamp: sensors.isNotEmpty
                        ? sensors.first.timestamp
                        : DateTime.now().toUtc(),
                    value: sensors.isNotEmpty
                        ? sensors
                                .map((s) => s.valueMm)
                                .reduce((a, b) => a + b) /
                            sensors.length
                        : 0,
                  ),
                ]
              : series;
          if (_selectedIndex >= _series.length) {
            _selectedIndex = _series.length - 1;
          }
        });
        _refreshMapSymbols();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load data. $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _refreshMapSymbols() {
    final controller = _mapController;
    if (controller == null) return;

    controller.removeSymbols(_symbols);
    _symbols.clear();
    _symbolIdToSensor.clear();

    for (final measurement in _measurements) {
      final color = colorForMeasurement(measurement.valueMm, _mode);
      controller
          .addSymbol(
        SymbolOptions(
          geometry: LatLng(measurement.lat, measurement.lon),
          iconImage: 'marker-15',
          iconColor: colorToRgbaString(color),
          textField: measurement.sensorId,
          textOffset: const Offset(0, 1.2),
          textSize: 10,
        ),
      )
          .then((symbol) {
        _symbols.add(symbol);
        _symbolIdToSensor[symbol.id] = measurement;
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
          _refreshMapSymbols();
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
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
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
            _measurements
                    .map((m) => m.lat)
                    .reduce((a, b) => a + b) /
                _measurements.length,
            _measurements
                    .map((m) => m.lon)
                    .reduce((a, b) => a + b) /
                _measurements.length,
          )
        : const LatLng(6.2442, -75.5812); // Medellín

    return MapboxMap(
      accessToken: mapboxAccessToken,
      initialCameraPosition: CameraPosition(target: center, zoom: 11),
      styleString: MapboxStyles.MAPBOX_STREETS,
      onMapCreated: (controller) {
        _mapController = controller;
        _mapController?.onSymbolTapped.add(_onSymbolTapped);
        _refreshMapSymbols();
      },
      onStyleLoadedCallback: _refreshMapSymbols,
      myLocationEnabled: false,
      compassEnabled: true,
      zoomGesturesEnabled: true,
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

  void _onSymbolTapped(Symbol symbol) async {
    final measurement = _symbolIdToSensor[symbol.id];
    if (measurement == null) return;

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
}
