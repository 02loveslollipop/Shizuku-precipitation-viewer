import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'api/api_client.dart';
import 'app_constants.dart';
import 'app_theme.dart';
import 'widgets/sensor_detail_sheet.dart';
import 'widgets/shizuku_app_bar.dart';

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
  bool _isGridLoading = false;
  String? _errorMessage;

  List<SensorMeasurement> _measurements = [];
  final Map<DateTime, GridSnapshot> _gridSnapshots = {};
  final Map<DateTime, _GridOverlayAssets> _gridOverlays = {};
  final Map<DateTime, GridSource> _gridSources = {};
  List<DateTime> _timeline = [];
  int _activeTimelineIndex = 0;
  DateTime? _selectedTimestamp;

  Uint8List? _heatmapImage;
  LatLngBounds? _gridBounds;
  List<Polyline> _contourPolylines = [];
  List<Polygon> _contourFills = [];

  bool _showPins = true;
  bool _showHeatmap = true;
  bool _showContours = true;

  Timer? _refreshTimer;
  bool _refreshInFlight = false;

  @override
  void initState() {
    super.initState();
    _loadData(initial: true);
    _refreshTimer = Timer.periodic(
      const Duration(minutes: 2),
      (_) => _loadData(silent: true),
    );
  }

  Future<void> _loadData({bool initial = false, bool silent = false}) async {
    if (_refreshInFlight) {
      return;
    }
    _refreshInFlight = true;
    if (initial) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
      // For initial load, use progressive loading approach
      await _loadDataProgressive();
    } else if (!silent) {
      setState(() {
        _isGridLoading = true;
      });
      // For refresh, still use the old approach for now
      await _loadDataLegacy();
    } else {
      // Silent refresh
      await _loadDataLegacy();
    }
    _refreshInFlight = false;
  }

  Future<void> _loadDataProgressive() async {
    try {
      // Load measurements and grid availability in parallel
      final measurementsFuture = _apiClient.fetchLatestMeasurements();
      final availabilityFuture = _apiClient.fetchGridAvailability();

      final sensors = await measurementsFuture;
      final availability = await availabilityFuture;

      if (!mounted) return;

      setState(() {
        _measurements = sensors;
        _errorMessage = null;
      });

      if (availability != null && availability.timestamps.isNotEmpty) {
        // Set up timeline
        _timeline = availability.timestamps;

        // Load latest grid data
        final latestTimestamp =
            availability.latest ?? availability.timestamps.first;
        await _loadGridForTimestamp(latestTimestamp, isInitial: true);
      } else {
        setState(() {
          _isLoading = false;
          _isGridLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Failed to load data. $e';
        _isLoading = false;
        _isGridLoading = false;
      });
    }
  }

  Future<void> _loadDataLegacy() async {
    try {
      final measurementsFuture = _apiClient.fetchLatestMeasurements();
      final gridFuture = _apiClient.fetchLatestGridBundle();

      final sensors = await measurementsFuture;
      final bundle = await gridFuture;

      _GridOverlayAssets? latestOverlay;
      if (bundle != null) {
        latestOverlay = await _buildGridOverlay(bundle.snapshot);
      }

      if (!mounted) return;

      setState(() {
        _measurements = sensors;
        _errorMessage = null;
        _isLoading = false;
      });

      if (bundle != null && latestOverlay != null) {
        _ingestGridBundle(bundle, latestOverlay);
      } else {
        setState(() {
          _isGridLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Failed to load data. $e';
        _isLoading = false;
        _isGridLoading = false;
      });
    }
  }

  void _ingestGridBundle(
    GridLatestBundle bundle,
    _GridOverlayAssets latestOverlay,
  ) {
    final previousSelection = _selectedTimestamp;
    final wasAtLatest =
        previousSelection == null ||
        (_timeline.isNotEmpty && previousSelection == _timeline.last);

    _gridSnapshots[bundle.snapshot.timestamp] = bundle.snapshot;
    _gridOverlays[bundle.snapshot.timestamp] = latestOverlay;
    _gridSources[bundle.snapshot.timestamp] = bundle.source;

    for (final entry in bundle.history) {
      _gridSources.putIfAbsent(entry.timestamp, () => entry.source);
    }

    final sorted = _gridSources.keys.toList()..sort();

    setState(() {
      _timeline = sorted;
    });

    if (_timeline.isEmpty) {
      setState(() {
        _heatmapImage = null;
        _gridBounds = null;
        _contourPolylines = [];
        _contourFills = [];
        _isGridLoading = false;
      });
      return;
    }

    if (wasAtLatest || !_timeline.contains(previousSelection)) {
      final latestTimestamp = _timeline.last;
      final resolvedOverlay = _gridOverlays[latestTimestamp] ?? latestOverlay;
      final resolvedSnapshot =
          _gridSnapshots[latestTimestamp] ?? bundle.snapshot;
      setState(() {
        _activeTimelineIndex = _timeline.length - 1;
        _selectedTimestamp = latestTimestamp;
        _updateActiveOverlay(resolvedSnapshot, resolvedOverlay);
        _isGridLoading = false;
      });
      return;
    }

    final index = _timeline.indexOf(previousSelection);
    setState(() {
      _activeTimelineIndex = index;
      _selectedTimestamp = previousSelection;
      final cachedOverlay = _gridOverlays[previousSelection];
      final cachedSnapshot = _gridSnapshots[previousSelection];
      if (cachedOverlay != null && cachedSnapshot != null) {
        _updateActiveOverlay(cachedSnapshot, cachedOverlay);
        _isGridLoading = false;
      } else {
        _isGridLoading = true;
      }
    });

    if (!_gridOverlays.containsKey(previousSelection)) {
      _ensureGridLoaded(previousSelection);
    }
  }

  Future<void> _ensureGridLoaded(DateTime timestamp) async {
    final cachedOverlay = _gridOverlays[timestamp];
    final cachedSnapshot = _gridSnapshots[timestamp];
    if (cachedOverlay != null && cachedSnapshot != null) {
      if (!mounted) return;
      setState(() {
        if (_selectedTimestamp == timestamp) {
          _updateActiveOverlay(cachedSnapshot, cachedOverlay);
        }
        _isGridLoading = false;
      });
      return;
    }

    final source = _gridSources[timestamp];
    if (source == null) {
      if (!mounted) return;
      setState(() {
        _isGridLoading = false;
      });
      return;
    }

    final snapshot = await _apiClient.fetchGridByUrl(
      source.gridUrl,
      contoursUrl: source.contoursUrl,
    );
    if (!mounted) return;
    if (snapshot == null) {
      setState(() {
        _isGridLoading = false;
      });
      return;
    }

    final overlay = await _buildGridOverlay(snapshot);
    if (!mounted) return;
    if (overlay == null) {
      setState(() {
        _isGridLoading = false;
      });
      return;
    }

    setState(() {
      _gridSnapshots[timestamp] = snapshot;
      _gridOverlays[timestamp] = overlay;
      if (_selectedTimestamp == timestamp) {
        _updateActiveOverlay(snapshot, overlay);
        _isGridLoading = false;
      }
    });
  }

  void _updateActiveOverlay(GridSnapshot snapshot, _GridOverlayAssets overlay) {
    _heatmapImage = overlay.heatmapPng;
    _gridBounds = overlay.bounds;
    _contourPolylines = overlay.contours;
    _contourFills = overlay.filledContours;
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _apiClient.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: const ShizukuAppBar(subtitle: 'Map viewer'),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
          ? _buildError(theme)
          : Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildSidebar(theme),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        Expanded(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(18),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.06),
                                  blurRadius: 16,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(18),
                              child: _buildMap(),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildTimelinePanel(theme),
                      ],
                    ),
                  ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _loadData(),
        icon: const Icon(Icons.refresh),
        label: const Text('Refresh'),
      ),
    );
  }

  Widget _buildMap() {
    final center = _measurements.isNotEmpty
        ? LatLng(
            _measurements.map((m) => m.lat).reduce((a, b) => a + b) /
                _measurements.length,
            _measurements.map((m) => m.lon).reduce((a, b) => a + b) /
                _measurements.length,
          )
        : const LatLng(6.2442, -75.5812);

    final layers = <Widget>[
      TileLayer(
        urlTemplate:
            'https://basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png',
        userAgentPackageName: 'com.shizuku.viewer',
        maxZoom: 19,
        minZoom: 2,
      ),
      if (_showHeatmap && _heatmapImage != null && _gridBounds != null)
        OverlayImageLayer(
          overlayImages: [
            OverlayImage(
              bounds: _gridBounds!,
              opacity: 0.78,
              imageProvider: MemoryImage(_heatmapImage!),
            ),
          ],
        ),
      if (_showContours && _contourFills.isNotEmpty)
        PolygonLayer(polygons: _contourFills),
      if (_showContours && _contourPolylines.isNotEmpty)
        PolylineLayer(polylines: _contourPolylines),
      if (_showPins) MarkerLayer(markers: _buildMarkers()),
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
          children: layers,
        ),
        if (_isGridLoading)
          const Positioned.fill(
            child: IgnorePointer(
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
        if (_selectedTimestamp != null)
          Positioned(
            top: 16,
            left: 16,
            child: _MapTimestampChip(timestamp: _selectedTimestamp!),
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
        .map<Marker>(
          (measurement) => Marker(
            point: LatLng(measurement.lat, measurement.lon),
            width: 42,
            height: 42,
            child: Builder(
              builder: (context) => _SensorMarker(
                measurement: measurement,
                onTap: () => _showSensorDetails(measurement),
              ),
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
      builder: (context) =>
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

  Widget _buildSidebar(ThemeData theme) {
    return Container(
      width: 260,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(right: BorderSide(color: Color(0x11000000), width: 1)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Overlays', style: theme.textTheme.titleMedium),
              const SizedBox(height: 12),
              _buildToggle(
                label: 'Pins',
                value: _showPins,
                onChanged: (value) => setState(() => _showPins = value),
              ),
              _buildToggle(
                label: 'Heat map',
                value: _showHeatmap,
                onChanged: (value) => setState(() => _showHeatmap = value),
              ),
              _buildToggle(
                label: 'Contours',
                value: _showContours,
                onChanged: (value) => setState(() => _showContours = value),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildLegendCard(theme),
                      const SizedBox(height: 24),
                      Text(
                        'Pin severity (mm)',
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 8),
                      _PinLegendRow(
                        color: colorForPinMeasurement(
                          pinGreenThresholdMm - 0.01,
                        ),
                        label: 'Low',
                        range:
                            '0 – ${pinGreenThresholdMm.toStringAsFixed(0)} mm',
                      ),
                      _PinLegendRow(
                        color: colorForPinMeasurement(
                          (pinGreenThresholdMm + pinAmberThresholdMm) / 2,
                        ),
                        label: 'Moderate',
                        range:
                            '${pinGreenThresholdMm.toStringAsFixed(0)} – ${pinAmberThresholdMm.toStringAsFixed(0)} mm',
                      ),
                      _PinLegendRow(
                        color: colorForPinMeasurement(
                          pinAmberThresholdMm + 0.01,
                        ),
                        label: 'High',
                        range: '> ${pinAmberThresholdMm.toStringAsFixed(0)} mm',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Data refreshes every 2 minutes.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: shizukuPrimary.withOpacity(0.6),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLegendCard(ThemeData theme) {
    final gradientStops = heatmapGradientStops();
    final gradientColors = heatmapGradientColors();
    final minValue = gradientStops.first;
    final maxValue = gradientStops.last;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Precipitation scale', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Container(
            height: 16,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              gradient: LinearGradient(colors: gradientColors),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${minValue.toStringAsFixed(0)} mm',
                style: theme.textTheme.bodySmall,
              ),
              Text(
                '${maxValue.toStringAsFixed(0)}+ mm',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final cls in intensityClasses)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    margin: const EdgeInsets.only(top: 4),
                    decoration: BoxDecoration(
                      color: colorForIntensityClass(
                        cls,
                        VisualizationMode.contour,
                      ),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(cls.label, style: theme.textTheme.bodyMedium),
                        Text(
                          cls.description,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: shizukuPrimary.withOpacity(0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildToggle({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return CheckboxListTile(
      value: value,
      onChanged: (checked) {
        if (checked != null) {
          onChanged(checked);
        }
      },
      dense: true,
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      title: Text(label),
    );
  }

  Widget _buildTimelinePanel(ThemeData theme) {
    if (_timeline.isEmpty) {
      return Container(
        height: 160,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Center(
          child: Text(
            'Timeline data is not available yet.',
            style: theme.textTheme.bodyMedium,
          ),
        ),
      );
    }

    final selectedTime = _timeline[_activeTimelineIndex];
    final isLatest = _activeTimelineIndex == _timeline.length - 1;
    final formatted = DateFormat('MMM d, HH:mm').format(selectedTime.toLocal());

    return Container(
      height: 180,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Map timeline', style: theme.textTheme.titleMedium),
              Row(
                children: [
                  if (isLatest) ...[
                    const Icon(
                      Icons.wifi_tethering,
                      size: 16,
                      color: shizukuPrimary,
                    ),
                    const SizedBox(width: 6),
                    Text('Live', style: theme.textTheme.bodySmall),
                    const SizedBox(width: 12),
                  ],
                  Text(formatted, style: theme.textTheme.bodySmall),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Slider(
            value: _activeTimelineIndex.toDouble(),
            min: 0,
            max: (_timeline.length - 1).toDouble(),
            divisions: _timeline.length > 1 ? _timeline.length - 1 : null,
            label: formatted,
            onChanged: _timeline.length > 1 ? _onTimelineSliderChanged : null,
          ),
          const SizedBox(height: 8),
          Text(
            'Drag the slider to inspect previous grid runs.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: shizukuPrimary.withOpacity(0.6),
            ),
          ),
        ],
      ),
    );
  }

  void _onTimelineSliderChanged(double value) {
    final index = value.round().clamp(0, _timeline.length - 1).toInt();
    if (index == _activeTimelineIndex) {
      return;
    }

    final target = _timeline[index];
    final cachedOverlay = _gridOverlays[target];
    final cachedSnapshot = _gridSnapshots[target];

    setState(() {
      _activeTimelineIndex = index;
      _selectedTimestamp = target;
      if (cachedOverlay != null && cachedSnapshot != null) {
        _updateActiveOverlay(cachedSnapshot, cachedOverlay);
        _isGridLoading = false;
      } else {
        _isGridLoading = true;
      }
    });

    if (cachedOverlay == null || cachedSnapshot == null) {
      _ensureGridLoaded(target);
    }
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

    final polylines = <Polyline>[];
    final filledContours = <Polygon>[];
    for (final feature in snapshot.contours) {
      if (feature.coordinates.length < 2) continue;
      final intensity = findIntensityClass(feature.thresholdMm);
      final strokeColor = colorForIntensityClass(
        intensity,
        VisualizationMode.contour,
      ).withOpacity(0.9);
      final points = feature.coordinates
          .map((pair) => LatLng(pair[1], pair[0]))
          .toList();
      polylines.add(
        Polyline(points: points, color: strokeColor, strokeWidth: 2),
      );

      final isClosed = points.length > 3 && _coordinatesClosed(points);
      if (isClosed) {
        filledContours.add(
          Polygon(
            points: points,
            color: strokeColor.withOpacity(0.25),
            borderColor: strokeColor,
            borderStrokeWidth: 1.2,
          ),
        );
      }
    }

    return _GridOverlayAssets(
      heatmapPng: pngBytes,
      bounds: bounds,
      contours: polylines,
      filledContours: filledContours,
    );
  }

  bool _coordinatesClosed(List<LatLng> points) {
    if (points.length < 3) {
      return false;
    }
    final first = points.first;
    final last = points.last;
    const epsilon = 1e-4;
    return (first.latitude - last.latitude).abs() < epsilon &&
        (first.longitude - last.longitude).abs() < epsilon;
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

  Future<void> _loadGridForTimestamp(
    DateTime timestamp, {
    bool isInitial = false,
  }) async {
    try {
      // Check if we already have this grid cached
      final cachedOverlay = _gridOverlays[timestamp];
      final cachedSnapshot = _gridSnapshots[timestamp];

      if (cachedOverlay != null && cachedSnapshot != null) {
        setState(() {
          _selectedTimestamp = timestamp;
          _activeTimelineIndex = _timeline.indexOf(timestamp);
          _updateActiveOverlay(cachedSnapshot, cachedOverlay);
          if (isInitial) _isLoading = false;
          _isGridLoading = false;
        });
        return;
      }

      // Fetch grid data from API
      final gridData = await _apiClient.fetchGridData(timestamp);
      if (gridData == null || gridData.gridUrl == null) {
        setState(() {
          if (isInitial) _isLoading = false;
          _isGridLoading = false;
        });
        return;
      }

      // Fetch the actual grid content from blob storage
      final snapshot = await _apiClient.fetchGridByUrl(
        gridData.gridUrl!,
        contoursUrl: gridData.contoursUrl,
      );

      if (snapshot == null) {
        setState(() {
          if (isInitial) _isLoading = false;
          _isGridLoading = false;
        });
        return;
      }

      // Build overlay assets
      final overlay = await _buildGridOverlay(snapshot);
      if (overlay == null) {
        setState(() {
          if (isInitial) _isLoading = false;
          _isGridLoading = false;
        });
        return;
      }

      if (!mounted) return;

      // Cache and update UI
      setState(() {
        _gridSnapshots[timestamp] = snapshot;
        _gridOverlays[timestamp] = overlay;
        _selectedTimestamp = timestamp;
        _activeTimelineIndex = _timeline.indexOf(timestamp);
        _updateActiveOverlay(snapshot, overlay);
        if (isInitial) _isLoading = false;
        _isGridLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (isInitial) {
          _errorMessage = 'Failed to load grid data: $e';
          _isLoading = false;
        }
        _isGridLoading = false;
      });
    }
  }
}

class _SensorMarker extends StatelessWidget {
  const _SensorMarker({required this.measurement, required this.onTap});

  final SensorMeasurement measurement;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = colorForPinMeasurement(measurement.valueMm);
    final severity = pinSeverityLabel(measurement.valueMm);
    final tooltip =
        '${measurement.name ?? measurement.sensorId}\n${measurement.valueMm.toStringAsFixed(2)} mm • $severity\nLat: ${measurement.lat.toStringAsFixed(4)}, Lon: ${measurement.lon.toStringAsFixed(4)}\nAddress: Pending lookup';

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Tooltip(
          message: tooltip,
          decoration: BoxDecoration(
            color: shizukuPrimary.withOpacity(0.9),
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: const TextStyle(color: Colors.white),
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
                  measurement.valueMm.toStringAsFixed(1),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  severity,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 8,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
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

class _PinLegendRow extends StatelessWidget {
  const _PinLegendRow({
    required this.color,
    required this.label,
    required this.range,
  });

  final Color color;
  final String label;
  final String range;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.bodyMedium),
                Text(
                  range,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: shizukuPrimary.withOpacity(0.6),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GridOverlayAssets {
  _GridOverlayAssets({
    required this.heatmapPng,
    required this.bounds,
    required this.contours,
    required this.filledContours,
  });

  final Uint8List heatmapPng;
  final LatLngBounds bounds;
  final List<Polyline> contours;
  final List<Polygon> filledContours;
}
