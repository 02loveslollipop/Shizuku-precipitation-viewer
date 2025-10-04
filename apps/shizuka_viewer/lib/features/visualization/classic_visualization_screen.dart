/// Classic Visualization Screen - Matches original UI design
///
/// Orchestrates modular components while maintaining exact original UI
/// Uses v1 API via providers

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../../core/providers/grid_provider.dart';
import '../../core/providers/dashboard_provider.dart';
import '../../core/api/api_models.dart';
import '../../models/presentation_models.dart';
import '../../widgets/shizuku_app_bar.dart';
import '../../widgets/sensor_detail_sheet.dart';
import '../map/simple_heatmap_widget.dart' as simple;
import '../map/simple_realtime_widget.dart' as simple;
import '../dashboard/dashboard_screen.dart';
import '../sidebar/classic_sidebar.dart';
import '../timeline/timeline_panel.dart';
import '../layout/classic_layouts.dart';
import '../../localization.dart';
import '../../app_constants.dart';

class ClassicVisualizationScreen extends StatefulWidget {
  const ClassicVisualizationScreen({super.key});

  @override
  State<ClassicVisualizationScreen> createState() =>
      _ClassicVisualizationScreenState();
}

class _ClassicVisualizationScreenState
    extends State<ClassicVisualizationScreen> {
  VisualizationMode _currentMode = VisualizationMode.heatmap;
  bool _showPins = true;
  bool _showHeatmap = true;
  bool _showContours = true;
  bool _mobileSidebarOpen = false;

  // Timeline state
  int _activeTimelineIndex = 0;
  Timer? _debounceTimer;

  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    // Schedule initial data load after the first frame to avoid setState during build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadInitialData();
    });
    _updateRefreshTimer();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _debounceTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    final gridProvider = context.read<GridProvider>();

    if (_currentMode == VisualizationMode.realtime) {
      await gridProvider.loadRealtimeMeasurements();
    } else if (_currentMode == VisualizationMode.heatmap) {
      await gridProvider.loadGridTimestamps();
      await gridProvider.loadLatestGrid();
    } else if (_currentMode == VisualizationMode.dashboard) {
      final dashProvider = context.read<DashboardProvider>();
      await dashProvider.loadSensors();
      await dashProvider.loadStats(period: TimePeriod.hours24);
    }
  }

  void _updateRefreshTimer() {
    _refreshTimer?.cancel();
    Duration interval;
    if (_currentMode == VisualizationMode.realtime) {
      interval = const Duration(minutes: 1);
    } else if (_currentMode == VisualizationMode.heatmap) {
      interval = const Duration(minutes: 10);
    } else {
      interval = const Duration(minutes: 5);
    }
    _refreshTimer = Timer.periodic(interval, (_) => _silentRefresh());
  }

  Future<void> _silentRefresh() async {
    final gridProvider = context.read<GridProvider>();

    if (_currentMode == VisualizationMode.realtime) {
      await gridProvider.loadRealtimeMeasurements();
    } else if (_currentMode == VisualizationMode.heatmap) {
      await gridProvider.loadGridTimestamps();
      if (gridProvider.timestamps.isNotEmpty &&
          _activeTimelineIndex == gridProvider.timestamps.length - 1) {
        await gridProvider.loadLatestGrid();
      }
    }
  }

  void _onModeChanged(VisualizationMode newMode) {
    setState(() {
      _currentMode = newMode;

      if (newMode == VisualizationMode.realtime) {
        _showPins = true;
        _showHeatmap = false;
        _showContours = false;
      } else if (newMode == VisualizationMode.heatmap) {
        _showPins = true;
        _showHeatmap = true;
        _showContours = true;
      }
    });

    _updateRefreshTimer();
    _loadInitialData();
  }

  void _onTimelineChanged(int index) {
    setState(() {
      _activeTimelineIndex = index;
    });

    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(seconds: 1), () {
      final gridProvider = context.read<GridProvider>();
      if (gridProvider.timestamps.isNotEmpty &&
          index < gridProvider.timestamps.length) {
        gridProvider.selectGridByIndex(index);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = LanguageScope.of(context);
    final isMobile = MediaQuery.of(context).size.width < 700;

    if (!isMobile && _mobileSidebarOpen) {
      _mobileSidebarOpen = false;
    }

    return Scaffold(
      appBar: ShizukuAppBar(
        subtitle: t.t('app.subtitle.mapViewer'),
        onMenuTap:
            isMobile
                ? () => setState(() => _mobileSidebarOpen = !_mobileSidebarOpen)
                : null,
        mode: _currentMode,
        onModeSelected: _onModeChanged,
      ),
      body: Consumer<GridProvider>(
        builder: (context, gridProvider, child) {
          final isLoading =
              gridProvider.isLoading && gridProvider.measurements.isEmpty;
          final errorMessage = gridProvider.error;

          if (isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (errorMessage != null) {
            return _buildError(theme, errorMessage);
          }

          return _buildMainContent(isMobile, gridProvider);
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loadInitialData,
        icon: const Icon(Icons.refresh),
        label: Text(LanguageScope.of(context).t('action.refresh')),
      ),
    );
  }

  Widget _buildMainContent(bool isMobile, GridProvider gridProvider) {
    final sidebar = ClassicSidebar(
      mode: _currentMode,
      showPins: _showPins,
      showHeatmap: _showHeatmap,
      showContours: _showContours,
      onPinsChanged: (value) => setState(() => _showPins = value),
      onHeatmapChanged: (value) => setState(() => _showHeatmap = value),
      onContoursChanged: (value) => setState(() => _showContours = value),
    );

    final content = _buildContentView(gridProvider);

    final timeline =
        _currentMode != VisualizationMode.realtime
            ? TimelinePanel(
              timestamps: gridProvider.timestamps,
              activeIndex: _activeTimelineIndex,
              onIndexChanged: _onTimelineChanged,
            )
            : null;

    if (isMobile) {
      return Stack(
        children: [
          MobileLayout(content: content, timeline: timeline),
          if (_mobileSidebarOpen)
            MobileSidebarOverlay(
              sidebar: sidebar,
              onClose: () => setState(() => _mobileSidebarOpen = false),
            ),
        ],
      );
    } else {
      return DesktopLayout(
        sidebar: sidebar,
        content: content,
        timeline: timeline,
      );
    }
  }

  Widget _buildContentView(GridProvider gridProvider) {
    if (_currentMode == VisualizationMode.dashboard) {
      return _buildDashboard();
    } else if (_currentMode == VisualizationMode.realtime) {
      return simple.RealtimeMapWidget(
        showPins: _showPins,
        onSensorTap: _showSensorDetails,
      );
    } else {
      return simple.HeatmapWidget(
        showPins: _showPins,
        showHeatmap: _showHeatmap,
        showContours: _showContours,
        onSensorTap: _showSensorDetails,
      );
    }
  }

  Widget _buildDashboard() {
    return Consumer<DashboardProvider>(
      builder: (context, dashProvider, child) {
        return const DashboardScreen();
      },
    );
  }

  Future<void> _showSensorDetails(
    Sensor sensor,
    Measurement measurement,
  ) async {
    final gridProvider = context.read<GridProvider>();

    final sensorMeasurement = SensorMeasurement.fromV1(
      sensor: sensor,
      measurement: measurement,
    );

    final measurements = await gridProvider.apiClient.getSensorMeasurements(
      sensor.id,
      clean: true,
      limit: 100,
    );

    if (!mounted) return;

    final history =
        measurements.measurements.map((m) => SeriesPoint.fromV1(m)).toList();

    showModalBottomSheet(
      context: context,
      builder:
          (context) => SensorDetailSheet(
            measurement: sensorMeasurement,
            history: history,
          ),
    );
  }

  Widget _buildError(ThemeData theme, String errorMessage) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              errorMessage,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadInitialData,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebar(ThemeData theme) {
    final t = LanguageScope.of(context);

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
              Text(t.t('overlays.title'), style: theme.textTheme.titleMedium),
              const SizedBox(height: 12),
              if (_currentMode == VisualizationMode.realtime) ...[
                _buildToggle(
                  label: t.t('overlay.pins'),
                  value: _showPins,
                  onChanged: (value) => setState(() => _showPins = value),
                ),
                const SizedBox(height: 24),
                Text(
                  t.t('sidebar.pinSeverity'),
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                _buildPinLegend(),
              ] else ...[
                _buildToggle(
                  label: t.t('overlay.pins'),
                  value: _showPins,
                  onChanged: (value) => setState(() => _showPins = value),
                ),
                _buildToggle(
                  label: t.t('overlay.heatmap'),
                  value: _showHeatmap,
                  onChanged: (value) => setState(() => _showHeatmap = value),
                ),
                _buildToggle(
                  label: t.t('toggle.contours'),
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
                          t.t('sidebar.pinSeverity'),
                          style: theme.textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 8),
                        _buildPinLegend(),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Text(
                t.t('refresh.info'),
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

  Widget _buildPinLegend() {
    final t = LanguageScope.of(context);
    return Column(
      children: [
        _PinLegendRow(
          color: colorForPinMeasurement(pinGreenThresholdMm - 0.01),
          label: t.t('pin.low'),
          range: '0 – ${pinGreenThresholdMm.toStringAsFixed(0)} mm',
        ),
        _PinLegendRow(
          color: colorForPinMeasurement(
            (pinGreenThresholdMm + pinAmberThresholdMm) / 2,
          ),
          label: t.t('pin.moderate'),
          range:
              '${pinGreenThresholdMm.toStringAsFixed(0)} – ${pinAmberThresholdMm.toStringAsFixed(0)} mm',
        ),
        _PinLegendRow(
          color: colorForPinMeasurement(pinAmberThresholdMm + 0.01),
          label: t.t('pin.high'),
          range: '> ${pinAmberThresholdMm.toStringAsFixed(0)} mm',
        ),
      ],
    );
  }

  Widget _buildLegendCard(ThemeData theme) {
    final t = LanguageScope.of(context);
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
          Text(t.t('precipitation.scale'), style: theme.textTheme.titleMedium),
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
                        VisualizationMode.heatmap,
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
                          t.t('intensity.${_intensityKey(cls)}.label'),
                          style: theme.textTheme.bodyMedium,
                        ),
                        Text(
                          t.t('intensity.${_intensityKey(cls)}.desc'),
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

  Widget _buildTimelinePanel(ThemeData theme, GridProvider gridProvider) {
    final t = LanguageScope.of(context);
    final timestamps = gridProvider.timestamps;

    if (timestamps.isEmpty) {
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
          child: Text(t.t('timeline.empty'), style: theme.textTheme.bodyMedium),
        ),
      );
    }

    final selectedTime = timestamps[_activeTimelineIndex];
    final isLatest = _activeTimelineIndex == timestamps.length - 1;
    final now = DateTime.now();
    final timeDiff = now.difference(selectedTime).abs();
    final isLive = isLatest && timeDiff.inMinutes < 10;

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
              Text(t.t('map.timeline'), style: theme.textTheme.titleMedium),
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
                      t.t('timeline.live'),
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(width: 12),
                  ] else if (isLatest) ...[
                    const Icon(Icons.schedule, size: 16, color: Colors.orange),
                    const SizedBox(width: 6),
                    Text(
                      t.t('timeline.latest'),
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
            max: (timestamps.length - 1).toDouble(),
            divisions: timestamps.length > 1 ? timestamps.length - 1 : null,
            label: formatted,
            onChanged:
                timestamps.length > 1
                    ? (value) => _onTimelineChanged(value.round())
                    : null,
          ),
          const SizedBox(height: 8),
          Text(
            t.t('timeline.dragSlider'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: shizukuPrimary.withOpacity(0.6),
            ),
          ),
        ],
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
