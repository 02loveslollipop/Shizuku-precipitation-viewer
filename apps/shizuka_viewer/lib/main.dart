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
import 'localization.dart';

void main() {
  Intl.defaultLocale = 'en_US';
  final lang = LanguageProvider();
  runApp(
    LanguageScope(notifier: lang, child: ShizukuViewerApp(language: lang)),
  );
}

class ShizukuViewerApp extends StatelessWidget {
  const ShizukuViewerApp({super.key, required this.language});

  final LanguageProvider language;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: language.t('app.title'),
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
  // Mobile-only: whether the compressed (button) sidebar is open
  bool _mobileSidebarOpen = false;

  Timer? _refreshTimer;
  bool _refreshInFlight = false;

  Timer? _debounceTimer;

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
      await _loadDataProgressive(initial: true, silent: silent);
    } else if (!silent) {
      setState(() {
        _isGridLoading = true;
      });
      // For refresh, still use the old approach for now
      await _loadDataLegacy(silent: false);
    } else {
      // Silent refresh
      await _loadDataLegacy(silent: true);
    }
    _refreshInFlight = false;
  }

  Future<void> _loadDataProgressive({
    bool initial = false,
    bool silent = false,
  }) async {
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
        // Preserve existing cached data when updating timeline
        final newTimeline = availability.timestamps;
        // Determine previous latest to decide whether we should auto-advance
        final previousLatest = _timeline.isNotEmpty ? _timeline.last : null;
        final wasSelectedLatest =
            previousLatest != null &&
            _selectedTimestamp != null &&
            _selectedTimestamp == previousLatest;

        // Update the timeline if it changed
        final timelineChanged =
            _timeline.isEmpty || !_listsEqual(_timeline, newTimeline);
        if (timelineChanged) {
          _timeline = newTimeline;
        }

        // Resolve the canonical latest timestamp from availability
        final latestTimestamp = availability.latest ?? _timeline.last;

        if (initial) {
          // First load: set selection to latest and load grid
          setState(() {
            final idx = _timeline.indexOf(latestTimestamp);
            _activeTimelineIndex = idx >= 0 ? idx : (_timeline.length - 1);
            _selectedTimestamp = latestTimestamp;
          });
          await _loadGridForTimestamp(latestTimestamp, isInitial: true);
        } else {
          // Non-initial (periodic or manual refresh):
          if (wasSelectedLatest) {
            // If user was at the latest point, advance to the new latest,
            // fetch sensors for that time and force-refresh overlays.
            setState(() {
              final idx = _timeline.indexOf(latestTimestamp);
              _activeTimelineIndex = idx >= 0 ? idx : (_timeline.length - 1);
              _selectedTimestamp = latestTimestamp;
              _isGridLoading = true;
            });
            // Refresh grid/overlays for the new selected latest
            await _loadGridForTimestamp(latestTimestamp);
          } else {
            // User is looking at an older time: do not move selection or
            // re-render overlays. Just update timeline entries if changed.
            if (timelineChanged) {
              setState(() {
                // only update the timeline list UI; do not change selection
              });
            }
            // No further action: keep current selection and overlays
          }
        }
      } else {
        setState(() {
          _isLoading = false;
          _isGridLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      // Don't show abort errors as user-facing errors
      final errorMessage =
          e.toString().contains('aborted') ||
                  e.toString().contains('AbortError')
              ? null
              : 'Failed to load data. $e';
      setState(() {
        _errorMessage = errorMessage;
        _isLoading = false;
        _isGridLoading = false;
      });
    }
  }

  Future<void> _loadDataLegacy({bool silent = false}) async {
    try {
      // Use progressive loading for refreshes too to preserve state
      await _loadDataProgressive(silent: silent);
    } catch (e) {
      if (!mounted) return;
      // Don't show abort errors as user-facing errors
      final errorMessage =
          e.toString().contains('aborted') ||
                  e.toString().contains('AbortError')
              ? null
              : 'Failed to load data. $e';
      setState(() {
        _errorMessage = errorMessage;
        _isLoading = false;
        _isGridLoading = false;
      });
    }
  }

  Future<void> _ensureGridLoaded(DateTime timestamp) async {
    final cachedOverlay = _gridOverlays[timestamp];
    final cachedSnapshot = _gridSnapshots[timestamp];
    if (cachedOverlay != null && cachedSnapshot != null) {
      if (!mounted) return;
      // Ensure pins are refreshed from API before applying cached overlay
      await _refreshAndApplyMeasurementsForTimestamp(timestamp);
      setState(() {
        if (_selectedTimestamp == timestamp) {
          _updateActiveOverlay(cachedSnapshot, cachedOverlay);
        }
        _isGridLoading = false;
      });
      return;
    }

    try {
      // Fetch grid metadata from API using the new progressive endpoint
      final gridData = await _apiClient.fetchGridData(timestamp);
      if (gridData == null || gridData.gridUrl == null) {
        if (!mounted) return;
        setState(() {
          _isGridLoading = false;
        });
        return;
      }

      // Fetch the actual grid content from blob storage
      final snapshot = await _apiClient.fetchGridByUrl(
        gridData.gridUrl!,
        contoursUrl: gridData.contoursUrl,
      );
      if (!mounted) return;
      if (snapshot == null) {
        setState(() {
          _isGridLoading = false;
        });
        return;
      }

      // Build overlay assets
      final overlay = await _buildGridOverlay(snapshot);
      if (!mounted) return;
      if (overlay == null) {
        setState(() {
          _isGridLoading = false;
        });
        return;
      }

      // Cache and update UI
      setState(() {
        _gridSnapshots[timestamp] = snapshot;
        _gridOverlays[timestamp] = overlay;
        if (_selectedTimestamp == timestamp) {
          _updateActiveOverlay(snapshot, overlay);
          _isGridLoading = false;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isGridLoading = false;
      });
      // Suppress logging for aborted/cancelled requests; other errors are
      // intentionally not logged here to avoid noisy output in production.
    }
  }

  void _updateActiveOverlay(GridSnapshot snapshot, _GridOverlayAssets overlay) {
    // Applied grid overlay for timestamp: ${snapshot.timestamp}
    _heatmapImage = overlay.heatmapPng;
    _gridBounds = overlay.bounds;
    _contourPolylines = overlay.contours;
    _contourFills = overlay.filledContours;
    // Update sensor measurements from the applied grid so pins reflect
    // the gridded values at the sensors' locations.
    _updateSensorsFromGrid(snapshot);
  }

  void _updateSensorsFromGrid(GridSnapshot snapshot) {
    // quick bounds and sizes
    final rows = snapshot.data.length;
    if (rows == 0) return;
    final cols = snapshot.data.first.length;
    if (cols == 0) return;

    // bbox values are available on snapshot if needed by sampling helper

    List<SensorMeasurement> updated = _measurements
        .map((m) {
          final sample = _sampleGridValueAtLatLng(snapshot, m.lat, m.lon);
          if (sample == null || sample.isNaN) {
            return m; // leave unchanged
          }
          return SensorMeasurement(
            sensorId: m.sensorId,
            name: m.name,
            city: m.city,
            lat: m.lat,
            lon: m.lon,
            valueMm: sample,
            timestamp: snapshot.timestamp,
          );
        })
        .toList(growable: false);

    setState(() {
      _measurements = updated;
    });
    // Updated ${updated.length} sensors from grid ${snapshot.timestamp}
  }

  double? _sampleGridValueAtLatLng(
    GridSnapshot snapshot,
    double lat,
    double lon,
  ) {
    final rows = snapshot.data.length;
    if (rows == 0) return null;
    final cols = snapshot.data.first.length;
    if (cols == 0) return null;

    // Map lat/lon to grid indices. Assume bbox: [west, south, east, north]
    final west = snapshot.west;
    final south = snapshot.south;
    final east = snapshot.east;
    final north = snapshot.north;

    if (lon < west || lon > east || lat < south || lat > north)
      return double.nan;

    final xFrac = (lon - west) / (east - west);
    final yFrac = (lat - south) / (north - south);

    final x = (xFrac * (cols - 1)).round().clamp(0, cols - 1);
    // grid rows are ordered north-to-south in snapshot.data? The code that
    // builds the image flipped rows; here assume data is [row0..rowN] from
    // north->south. If this is inverted, sampling will need to flip y.
    final y = ((1 - yFrac) * (rows - 1)).round().clamp(0, rows - 1);

    final value = snapshot.data[y][x];
    // Values cannot be negative: clamp negatives to 0. Keep NaN/Infinity as-is.
    if (value.isNaN) return value;
    if (value.isFinite) {
      return value < 0.0 ? 0.0 : value;
    }
    return value;
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _debounceTimer?.cancel();
    _apiClient.dispose();
    super.dispose();
  }

  bool _listsEqual(List<DateTime> a, List<DateTime> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = LanguageScope.of(context);
    final isMobile = MediaQuery.of(context).size.width < 700;
    // If we're no longer mobile, ensure mobile sidebar is closed
    if (!isMobile && _mobileSidebarOpen) {
      _mobileSidebarOpen = false;
    }
    return Scaffold(
      appBar: ShizukuAppBar(subtitle: t.t('app.subtitle.mapViewer')),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _errorMessage != null
              ? _buildError(theme)
              : (isMobile
                  // Mobile: map fills screen and sidebar is toggled via button
                  ? Stack(
                    children: [
                      Padding(
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
                      // Menu button to open sidebar
                      Positioned(
                        top: 20,
                        left: 20,
                        child: FloatingActionButton.small(
                          onPressed:
                              () => setState(
                                () => _mobileSidebarOpen = !_mobileSidebarOpen,
                              ),
                          child: const Icon(Icons.menu),
                        ),
                      ),
                      // Sidebar overlay
                      if (_mobileSidebarOpen)
                        Positioned.fill(
                          child: Row(
                            children: [
                              // Sidebar panel (tap inside should not close)
                              SizedBox(
                                width: 260,
                                child: Material(
                                  elevation: 8,
                                  child: SafeArea(child: _buildSidebar(theme)),
                                ),
                              ),
                              // Backdrop: tapping closes the sidebar
                              Expanded(
                                child: GestureDetector(
                                  onTap:
                                      () => setState(
                                        () => _mobileSidebarOpen = false,
                                      ),
                                  child: Container(
                                    color: Colors.black.withOpacity(0.35),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  )
                  // Desktop/iPad: original layout with left sidebar
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
                  )),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _loadData(),
        icon: const Icon(Icons.refresh),
        label: Text(LanguageScope.of(context).t('action.refresh')),
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

    // Define bounds for Antioquia region to limit zoom out
    const antioaquiaSouth = 4.8;
    const antioaquiaNorth = 8.8;
    const antioaquiaWest = -77.2;
    const antioaquiaEast = -73.5;

    final layers = <Widget>[
      TileLayer(
        urlTemplate:
            'https://basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png',
        userAgentPackageName: 'com.shizuku.viewer',
        maxZoom: 19,
        minZoom: 8, // Increased minimum zoom to keep focus on region
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
            minZoom: 8.0, // Prevent zooming out too far
            maxZoom: 19.0,
            onPositionChanged: (position, hasGesture) {
              // Enforce bounds for Antioquia region
              if (hasGesture) {
                // Check if center is outside bounds and adjust if needed
                final center = position.center;
                double newLat = center.latitude;
                double newLng = center.longitude;

                if (center.latitude < antioaquiaSouth) newLat = antioaquiaSouth;
                if (center.latitude > antioaquiaNorth) newLat = antioaquiaNorth;
                if (center.longitude < antioaquiaWest) newLng = antioaquiaWest;
                if (center.longitude > antioaquiaEast) newLng = antioaquiaEast;

                if (newLat != center.latitude || newLng != center.longitude) {
                  Future.microtask(() {
                    _mapController.move(LatLng(newLat, newLng), position.zoom);
                  });
                }
              }
            },
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
            ),
          ),
          children: layers,
        ),
        if (_isGridLoading)
          Positioned.fill(
            child: IgnorePointer(
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
              builder:
                  (context) => _SensorMarker(
                    measurement: measurement,
                    onTap: () => _showSensorDetails(measurement),
                  ),
            ),
          ),
        )
        .toList();
  }

  Future<void> _showSensorDetails(SensorMeasurement measurement) async {
    try {
      final history = await _apiClient.fetchSensorHistory(measurement.sensorId);
      if (!mounted) return;

      showModalBottomSheet(
        context: context,
        builder:
            (context) =>
                SensorDetailSheet(measurement: measurement, history: history),
      );
    } catch (e) {
      if (!mounted) return;
      // Don't show abort errors as user-facing errors
      if (!e.toString().contains('aborted') &&
          !e.toString().contains('AbortError')) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load sensor history: $e')),
        );
      }
    }
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
              Text(
                LanguageScope.of(context).t('overlays.title'),
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              _buildToggle(
                label: LanguageScope.of(context).t('overlay.pins'),
                value: _showPins,
                onChanged: (value) => setState(() => _showPins = value),
              ),
              _buildToggle(
                label: LanguageScope.of(context).t('overlay.heatmap'),
                value: _showHeatmap,
                onChanged: (value) => setState(() => _showHeatmap = value),
              ),
              _buildToggle(
                label: LanguageScope.of(context).t('toggle.contours'),
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
                        LanguageScope.of(context).t('sidebar.pinSeverity'),
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 8),
                      _PinLegendRow(
                        color: colorForPinMeasurement(
                          pinGreenThresholdMm - 0.009,
                        ),
                        label: LanguageScope.of(context).t('pin.low'),
                        range:
                            '0 – ${pinGreenThresholdMm.toStringAsFixed(0)} mm',
                      ),
                      _PinLegendRow(
                        color: colorForPinMeasurement(
                          (pinGreenThresholdMm + pinAmberThresholdMm) / 2,
                        ),
                        label: LanguageScope.of(context).t('pin.moderate'),
                        range:
                            '${pinGreenThresholdMm.toStringAsFixed(0)} – ${pinAmberThresholdMm.toStringAsFixed(0)} mm',
                      ),
                      _PinLegendRow(
                        color: colorForPinMeasurement(
                          pinAmberThresholdMm + 0.009,
                        ),
                        label: LanguageScope.of(context).t('pin.high'),
                        range: '> ${pinAmberThresholdMm.toStringAsFixed(0)} mm',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                LanguageScope.of(context).t('refresh.info'),
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
          Text(
            LanguageScope.of(context).t('precipitation.scale'),
            style: theme.textTheme.titleMedium,
          ),
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
                        Text(
                          LanguageScope.of(
                            context,
                          ).t('intensity.' + _intensityKey(cls) + '.label'),
                          style: theme.textTheme.bodyMedium,
                        ),
                        Text(
                          LanguageScope.of(
                            context,
                          ).t('intensity.' + _intensityKey(cls) + '.desc'),
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

  String _intensityKey(IntensityClass cls) {
    final label = cls.label.toLowerCase();
    if (label.startsWith('trace')) return 'trace';
    if (label.startsWith('light')) return 'light';
    if (label.startsWith('moderate')) return 'moderate';
    if (label.startsWith('heavy')) return 'heavy';
    if (label.startsWith('intense')) return 'intense';
    return 'violent';
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
            LanguageScope.of(context).t('timeline.empty'),
            style: theme.textTheme.bodyMedium,
          ),
        ),
      );
    }

    final selectedTime = _timeline[_activeTimelineIndex];
    final isLatest = _activeTimelineIndex == _timeline.length - 1;
    final now = DateTime.now();
    final timeDiff = now.difference(selectedTime).abs();
    final isLive =
        isLatest &&
        timeDiff.inMinutes < 10; // Consider live if within 10 minutes

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
              Text(
                LanguageScope.of(context).t('map.timeline'),
                style: theme.textTheme.titleMedium,
              ),
              Row(
                children: [
                  if (isLive) ...[
                    const Icon(
                      Icons.wifi_tethering,
                      size: 16,
                      color: shizukuPrimary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      LanguageScope.of(context).t('timeline.live'),
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(width: 12),
                  ] else if (isLatest) ...[
                    const Icon(Icons.schedule, size: 16, color: Colors.orange),
                    const SizedBox(width: 6),
                    Text(
                      LanguageScope.of(context).t('timeline.latest'),
                      style: theme.textTheme.bodySmall,
                    ),
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
            LanguageScope.of(context).t('timeline.dragSlider'),
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

    setState(() {
      _activeTimelineIndex = index;
      _selectedTimestamp = target;
      // Don't update overlay immediately - wait for debounce
    });

    // Cancel any pending debounce timer
    _debounceTimer?.cancel();
    // Start a new timer to update data after 1 second
    _debounceTimer = Timer(const Duration(seconds: 1), () async {
      // Always refresh sensor measurements from API for the target timestamp
      // This ensures pins reflect the latest station data before applying
      // gridded overrides.
      await _refreshAndApplyMeasurementsForTimestamp(target);

      final cachedOverlay = _gridOverlays[target];
      final cachedSnapshot = _gridSnapshots[target];

      setState(() {
        if (cachedOverlay != null && cachedSnapshot != null) {
          _updateActiveOverlay(cachedSnapshot, cachedOverlay);
          _isGridLoading = false;
        } else {
          _isGridLoading = true;
        }
      });

      if (cachedOverlay == null || cachedSnapshot == null) {
        await _ensureGridLoaded(target);
      }
    });
  }

  /// Fetch latest sensor measurements from the API and then, if a grid
  /// snapshot for [timestamp] is already available, apply sampled overrides
  /// so pins reflect grid values. This is intentionally forced on timeline
  /// changes so pins always show up-to-date station values and then the
  /// gridded values are applied.
  Future<void> _refreshAndApplyMeasurementsForTimestamp(
    DateTime timestamp,
  ) async {
    try {
      // Try the snapshot endpoint (one request for all sensors at-or-before timestamp).
      List<SensorMeasurement> sensors;
      try {
        sensors = await _apiClient.fetchMeasurementsSnapshot(
          timestamp,
          clean: true,
        );
      } catch (e) {
        // If snapshot endpoint is not available or fails, fall back to the
        // existing /sensor + /now approach. Do not log to avoid noisy output.
        sensors = await _apiClient.fetchLatestMeasurements();
      }
      if (!mounted) return;

      // Update measurements with fresh API values first
      setState(() {
        _measurements = sensors;
      });

      // If we already have a grid snapshot for this timestamp, sample and
      // override sensor values so pins reflect the grid.
      final snapshot = _gridSnapshots[timestamp];
      if (snapshot != null) {
        _updateSensorsFromGrid(snapshot);
      }
    } catch (e) {
      if (!mounted) return;
      // Suppress abort/cancel errors as they're expected in some network
      // environments. Log others for debugging.
      // Errors are intentionally not logged to avoid polluting console output
      // during normal operation. Aborted requests are common when users
      // interact rapidly with the UI.
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
        if (value.isNaN || value < 0.009) {
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
      final points =
          feature.coordinates.map((pair) => LatLng(pair[1], pair[0])).toList();
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
        // Refresh sensor measurements before applying the cached overlay so
        // pins reflect the freshest station values prior to overlay.
        await _refreshAndApplyMeasurementsForTimestamp(timestamp);
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

      // Before caching and updating UI, refresh station measurements so
      // pins first show fresh API values; the subsequent _updateActiveOverlay
      // will sample the grid and override them as needed.
      await _refreshAndApplyMeasurementsForTimestamp(timestamp);

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
      // Don't show abort errors as user-facing errors
      final errorMessage =
          e.toString().contains('aborted') ||
                  e.toString().contains('AbortError')
              ? null
              : 'Failed to load grid data: $e';
      setState(() {
        if (isInitial) {
          _errorMessage = errorMessage;
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
    final severityKey = pinSeverityKey(measurement.valueMm);
    final severityLabel = LanguageScope.of(context).t(severityKey);
    final tooltip =
        '${measurement.name ?? measurement.sensorId}\n${measurement.valueMm.toStringAsFixed(4)} mm • $severityLabel\nLat: ${measurement.lat.toStringAsFixed(4)}, Lon: ${measurement.lon.toStringAsFixed(4)}\nAddress: Pending lookup';

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
                  severityLabel,
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
