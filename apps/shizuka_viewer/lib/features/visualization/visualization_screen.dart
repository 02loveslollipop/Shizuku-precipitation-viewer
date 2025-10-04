import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:latlong2/latlong.dart';

import '../../core/providers/sensor_provider.dart';
import '../../core/providers/grid_provider.dart';
import '../../core/providers/dashboard_provider.dart';
import '../map/heatmap_widget.dart';
import '../map/realtime_map_widget.dart';
import '../dashboard/dashboard_screen.dart';
import '../sidebar/modular_sidebar.dart';
import '../sidebar/sidebar_config.dart';
import '../../localization.dart';
import '../../app_constants.dart';

enum VisualizationMode { heatmap, realtime, dashboard }

class VisualizationScreen extends StatefulWidget {
  const VisualizationScreen({super.key});

  @override
  State<VisualizationScreen> createState() => _VisualizationScreenState();
}

class _VisualizationScreenState extends State<VisualizationScreen> {
  VisualizationMode _currentMode = VisualizationMode.heatmap;
  bool _showPins = true;
  bool _showHeatmap = true;
  bool _showContours = true;
  bool _mobileSidebarOpen = false;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    final gridProvider = context.read<GridProvider>();
    final dashboardProvider = context.read<DashboardProvider>();

    await Future.wait([
      gridProvider.loadRealtimeMeasurements(),
      gridProvider.loadLatestGrid(),
      dashboardProvider.loadSensors(),
    ]);
  }

  void _onModeChanged(VisualizationMode newMode) {
    setState(() {
      _currentMode = newMode;
      
      // Adjust defaults based on mode
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

    // Trigger appropriate data reload
    if (newMode == VisualizationMode.realtime) {
      context.read<GridProvider>().loadRealtimeMeasurements();
    } else if (newMode == VisualizationMode.heatmap) {
      context.read<GridProvider>().loadLatestGrid();
    } else if (newMode == VisualizationMode.dashboard) {
      context.read<DashboardProvider>().loadSensors();
    }
  }

  List<SidebarSection> _buildSidebarSections() {
    final t = LanguageScope.of(context);
    
    return [
      SidebarSection(
        title: t.t('sidebar.mode'),
        options: [
          SidebarOption(
            id: 'mode',
            label: t.t('sidebar.mode'),
            icon: Icons.layers,
            type: SidebarOptionType.radio,
            radioOptions: [
              t.t('mode.heatmap'),
              t.t('mode.realtime'),
              t.t('mode.dashboard'),
            ],
            selectedRadioIndex: _currentMode.index,
            onRadioChanged: (index) {
              _onModeChanged(VisualizationMode.values[index]);
            },
          ),
        ],
      ),
      if (_currentMode != VisualizationMode.dashboard)
        SidebarSection(
          title: t.t('overlays.title'),
          options: [
            SidebarOption(
              id: 'show_pins',
              label: t.t('overlay.pins'),
              icon: Icons.location_on,
              type: SidebarOptionType.toggle,
              value: _showPins,
              onToggleChanged: (value) {
                setState(() => _showPins = value);
              },
            ),
            if (_currentMode != VisualizationMode.realtime) ...[
              SidebarOption(
                id: 'show_heatmap',
                label: t.t('overlay.heatmap'),
                icon: Icons.grid_on,
                type: SidebarOptionType.toggle,
                value: _showHeatmap,
                onToggleChanged: (value) {
                  setState(() => _showHeatmap = value);
                },
              ),
              SidebarOption(
                id: 'show_contours',
                label: t.t('toggle.contours'),
                icon: Icons.show_chart,
                type: SidebarOptionType.toggle,
                value: _showContours,
                onToggleChanged: (value) {
                  setState(() => _showContours = value);
                },
              ),
            ],
          ],
        ),
      if (_currentMode != VisualizationMode.dashboard)
        SidebarSection(
          title: t.t('sidebar.pinSeverity'),
          options: [
            SidebarOption(
              id: 'legend',
              label: '',
              icon: Icons.info,
              type: SidebarOptionType.custom,
              customWidget: _buildPinLegend(),
            ),
          ],
        ),
    ];
  }

  Widget _buildPinLegend() {
    final t = LanguageScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PinLegendRow(
          color: colorForPinMeasurement(pinGreenThresholdMm - 0.01),
          label: t.t('pin.low'),
          range: '0 – ${pinGreenThresholdMm.toStringAsFixed(0)} mm',
        ),
        const SizedBox(height: 8),
        _PinLegendRow(
          color: colorForPinMeasurement(
            (pinGreenThresholdMm + pinAmberThresholdMm) / 2,
          ),
          label: t.t('pin.moderate'),
          range:
              '${pinGreenThresholdMm.toStringAsFixed(0)} – ${pinAmberThresholdMm.toStringAsFixed(0)} mm',
        ),
        const SizedBox(height: 8),
        _PinLegendRow(
          color: colorForPinMeasurement(pinAmberThresholdMm + 0.01),
          label: t.t('pin.high'),
          range: '> ${pinAmberThresholdMm.toStringAsFixed(0)} mm',
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 700;
    
    if (!isMobile && _mobileSidebarOpen) {
      _mobileSidebarOpen = false;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(LanguageScope.of(context).t('app.title')),
        leading:
            isMobile
                ? IconButton(
                  icon: const Icon(Icons.menu),
                  onPressed: () {
                    setState(() => _mobileSidebarOpen = !_mobileSidebarOpen);
                  },
                )
                : null,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadInitialData,
          ),
        ],
      ),
      body:
          isMobile
              ? _buildMobileLayout()
              : _buildDesktopLayout(),
      floatingActionButton:
          _currentMode != VisualizationMode.dashboard
              ? FloatingActionButton(
                onPressed: _loadInitialData,
                child: const Icon(Icons.refresh),
              )
              : null,
    );
  }

  Widget _buildMobileLayout() {
    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
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
              child: _buildMainContent(),
            ),
          ),
        ),
        if (_mobileSidebarOpen)
          Positioned.fill(
            child: Row(
              children: [
                SizedBox(
                  width: 260,
                  child: Material(
                    elevation: 8,
                    child: SafeArea(
                      child: ModularSidebar(
                        sections: _buildSidebarSections(),
                        width: 260,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() => _mobileSidebarOpen = false);
                    },
                    child: Container(
                      color: Colors.black.withOpacity(0.35),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildDesktopLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ModularSidebar(
          sections: _buildSidebarSections(),
          width: 260,
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
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
                child: _buildMainContent(),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMainContent() {
    // Default center for Antioquia
    final defaultCenter = LatLng(6.2442, -75.5812);
    
    switch (_currentMode) {
      case VisualizationMode.heatmap:
        return Consumer2<GridProvider, SensorProvider>(
          builder: (context, gridProvider, sensorProvider, child) {
            if (gridProvider.isLoading) {
              return const Center(child: CircularProgressIndicator());
            }
            if (gridProvider.error != null) {
              return Center(child: Text('Error: ${gridProvider.error}'));
            }
            if (gridProvider.latestGrid == null) {
              return const Center(child: Text('No grid data available'));
            }
            
            return HeatmapWidget(
              initialCenter: defaultCenter,
              gridData: gridProvider.selectedGrid,
              sensors: sensorProvider.sensors,
              showSensors: _showPins,
              showHeatmap: _showHeatmap,
              showContours: _showContours,
            );
          },
        );
      
      case VisualizationMode.realtime:
        return Consumer<GridProvider>(
          builder: (context, gridProvider, child) {
            if (gridProvider.loadingRealtime) {
              return const Center(child: CircularProgressIndicator());
            }
            if (gridProvider.error != null) {
              return Center(child: Text('Error: ${gridProvider.error}'));
            }
            if (gridProvider.realtimeMeasurements == null ||
                gridProvider.realtimeMeasurements!.measurements.isEmpty) {
              return const Center(child: Text('No sensor data available'));
            }
            
            return RealtimeMapWidget(
              initialCenter: defaultCenter,
              measurements: gridProvider.realtimeMeasurements!.measurements,
            );
          },
        );
      
      case VisualizationMode.dashboard:
        return const DashboardScreen();
    }
  }
}

class _PinLegendRow extends StatelessWidget {
  final Color color;
  final String label;
  final String range;

  const _PinLegendRow({
    required this.color,
    required this.label,
    required this.range,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 4,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: 12,
                ),
              ),
              Text(
                range,
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
