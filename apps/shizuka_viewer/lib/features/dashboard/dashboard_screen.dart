/// Dashboard Screen
/// 
/// Main dashboard with statistics and sensor analytics

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/providers/dashboard_provider.dart';
import 'period_selector.dart';
import 'sensor_selector.dart';
import 'max_precipitation_card.dart';
import 'sensor_stats_card.dart';
import 'charts/precipitation_chart.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({Key? key}) : super(key: key);

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  TimePeriod _selectedPeriod = TimePeriod.hours24;
  String? _selectedSensorId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  Future<void> _loadData() async {
    final provider = context.read<DashboardProvider>();
    await provider.loadSensors();
    await provider.loadStats(period: _selectedPeriod);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Consumer<DashboardProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading && provider.sensors.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          if (provider.error != null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
                  const SizedBox(height: 16),
                  Text(
                    'Error: ${provider.error}',
                    style: Theme.of(context).textTheme.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _loadData,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Period selector
                PeriodSelector(
                  selectedPeriod: _selectedPeriod,
                  onPeriodChanged: (period) async {
                    setState(() => _selectedPeriod = period);
                    await provider.loadStats(period: period);
                    if (_selectedSensorId != null) {
                      await provider.loadSensorStats(_selectedSensorId!, period);
                    }
                  },
                ),

                const SizedBox(height: 24),

                // Max precipitation section
                _buildMaxPrecipitationSection(provider),

                const SizedBox(height: 24),

                // Sensor selector
                if (provider.sensors.isNotEmpty)
                  SensorSelector(
                    sensors: provider.sensors,
                    selectedSensorId: _selectedSensorId,
                    onSensorChanged: (sensorId) async {
                      setState(() => _selectedSensorId = sensorId);
                      await provider.loadSensorStats(sensorId, _selectedPeriod);
                    },
                  ),

                const SizedBox(height: 16),

                // Sensor statistics
                if (provider.loadingSensorStats)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(40),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  ),

                if (!provider.loadingSensorStats &&
                    provider.selectedSensorStats != null)
                  _buildSensorStatsSection(provider),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildMaxPrecipitationSection(DashboardProvider provider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Maximum Precipitation',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            MaxPrecipitationCard(
              title: 'Highest Rate',
              stats: provider.maxStats,
              period: _selectedPeriod,
            ),
            MaxPrecipitationCard(
              title: 'Total Accumulation',
              stats: provider.totalStats,
              period: _selectedPeriod,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSensorStatsSection(DashboardProvider provider) {
    final stats = provider.selectedSensorStats;
    if (stats == null) return const SizedBox();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SensorStatsCard(stats: stats),
        const SizedBox(height: 16),
        PrecipitationChart(
          data: stats.timeseries,
          period: _selectedPeriod,
        ),
      ],
    );
  }
}
