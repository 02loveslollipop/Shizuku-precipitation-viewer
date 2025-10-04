/// Max Precipitation Card
/// 
/// Displays maximum precipitation statistics for a period

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/api/api_models.dart';
import '../../core/providers/dashboard_provider.dart';

class MaxPrecipitationCard extends StatelessWidget {
  final String title;
  final PrecipitationStats? stats;
  final TimePeriod period;

  const MaxPrecipitationCard({
    Key? key,
    required this.title,
    required this.stats,
    required this.period,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (stats == null) {
      return _buildEmptyCard(context);
    }

    return Card(
      elevation: 2,
      child: Container(
        width: 280,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.water_drop,
                  color: _getIntensityColor(stats!.maxValue),
                  size: 32,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              '${stats!.maxValue.toStringAsFixed(2)} mm/h',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: _getIntensityColor(stats!.maxValue),
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              stats!.sensorName,
              style: Theme.of(context).textTheme.bodyMedium,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              _formatTimestamp(stats!.timestamp),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey[600],
                  ),
            ),
            const SizedBox(height: 12),
            _buildStatRow('Average', '${stats!.avgValue.toStringAsFixed(2)} mm/h'),
            _buildStatRow('Median', '${stats!.medianValue.toStringAsFixed(2)} mm/h'),
            _buildStatRow('Active Sensors', '${stats!.activeSensorCount}'),
          ],
        ),
      ),
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(color: Colors.grey[600], fontSize: 13),
          ),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyCard(BuildContext context) {
    return Card(
      elevation: 2,
      child: Container(
        width: 280,
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(Icons.analytics_outlined, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 12),
            Text(
              'No data available',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'for ${period.label}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey[600],
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getIntensityColor(double mmH) {
    if (mmH >= 50) return Colors.red[900]!;
    if (mmH >= 20) return Colors.red[600]!;
    if (mmH >= 10) return Colors.orange[700]!;
    if (mmH >= 5) return Colors.orange[400]!;
    if (mmH >= 2) return Colors.yellow[700]!;
    if (mmH >= 0.5) return Colors.lightBlue;
    return Colors.grey;
  }

  String _formatTimestamp(DateTime dt) {
    final formatter = DateFormat('MMM d, y HH:mm');
    return formatter.format(dt);
  }
}
