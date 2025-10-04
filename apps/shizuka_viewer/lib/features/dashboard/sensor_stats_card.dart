/// Sensor Statistics Card
/// 
/// Displays detailed statistics for a selected sensor

import 'package:flutter/material.dart';
import '../../core/api/api_models.dart';

class SensorStatsCard extends StatelessWidget {
  final SensorStats stats;

  const SensorStatsCard({
    Key? key,
    required this.stats,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: Theme.of(context).primaryColor,
                  child: const Icon(Icons.sensors, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        stats.sensorName,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text(
                        stats.sensorId,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.grey[600],
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            _buildStatsGrid(context),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsGrid(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 2.5,
      mainAxisSpacing: 16,
      crossAxisSpacing: 16,
      children: [
        _StatItem(
          label: 'Total Precipitation',
          value: '${stats.totalPrecipitation.toStringAsFixed(2)} mm',
          icon: Icons.water_drop,
          color: Colors.blue,
        ),
        _StatItem(
          label: 'Average Rate',
          value: '${stats.avgRate.toStringAsFixed(2)} mm/h',
          icon: Icons.speed,
          color: Colors.green,
        ),
        _StatItem(
          label: 'Peak Intensity',
          value: '${stats.peakIntensity.toStringAsFixed(2)} mm/h',
          icon: Icons.trending_up,
          color: Colors.orange,
        ),
        _StatItem(
          label: 'Data Points',
          value: '${stats.dataPointCount}',
          icon: Icons.insights,
          color: Colors.purple,
        ),
        _StatItem(
          label: 'Rainy Periods',
          value: '${stats.rainyPeriodCount}',
          icon: Icons.cloud,
          color: Colors.indigo,
        ),
        _StatItem(
          label: 'Dry Periods',
          value: '${stats.dryPeriodCount}',
          icon: Icons.wb_sunny,
          color: Colors.amber,
        ),
      ],
    );
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatItem({
    Key? key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[700],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
