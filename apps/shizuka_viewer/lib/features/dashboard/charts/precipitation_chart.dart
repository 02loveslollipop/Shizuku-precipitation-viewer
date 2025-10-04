/// Precipitation Chart
/// 
/// Line chart showing precipitation over time

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../../../core/api/api_models.dart';
import '../../../core/providers/dashboard_provider.dart';

class PrecipitationChart extends StatelessWidget {
  final List<TimeSeriesData> data;
  final TimePeriod period;

  const PrecipitationChart({
    Key? key,
    required this.data,
    required this.period,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return Card(
        elevation: 2,
        child: Container(
          height: 250,
          padding: const EdgeInsets.all(20),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.show_chart, size: 48, color: Colors.grey[400]),
                const SizedBox(height: 12),
                Text(
                  'No data available',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Precipitation Over Time',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 250,
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: _getHorizontalInterval(),
                  ),
                  titlesData: _buildTitlesData(),
                  borderData: FlBorderData(
                    show: true,
                    border: Border(
                      left: BorderSide(color: Colors.grey[300]!),
                      bottom: BorderSide(color: Colors.grey[300]!),
                    ),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: _buildSpots(),
                      isCurved: true,
                      color: Colors.blue,
                      barWidth: 3,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: true,
                        color: Colors.blue.withOpacity(0.3),
                      ),
                    ),
                  ],
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipItems: (spots) {
                        return spots.map((spot) {
                          final index = spot.spotIndex;
                          if (index >= 0 && index < data.length) {
                            final dt = data[index].timestamp;
                            final formatter = DateFormat('MMM d, HH:mm');
                            return LineTooltipItem(
                              '${formatter.format(dt)}\n${spot.y.toStringAsFixed(2)} mm',
                              const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            );
                          }
                          return null;
                        }).toList();
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<FlSpot> _buildSpots() {
    return data.asMap().entries.map((entry) {
      return FlSpot(entry.key.toDouble(), entry.value.value);
    }).toList();
  }

  FlTitlesData _buildTitlesData() {
    return FlTitlesData(
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 40,
          getTitlesWidget: (value, meta) {
            return Text(
              value.toStringAsFixed(1),
              style: const TextStyle(fontSize: 10),
            );
          },
        ),
      ),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 30,
          interval: _getBottomInterval(),
          getTitlesWidget: (value, meta) {
            final index = value.toInt();
            if (index >= 0 && index < data.length) {
              final dt = data[index].timestamp;
              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _formatBottomLabel(dt),
                  style: const TextStyle(fontSize: 9),
                ),
              );
            }
            return const Text('');
          },
        ),
      ),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    );
  }

  double _getBottomInterval() {
    if (data.length < 10) return 1;
    return (data.length / 8).ceilToDouble();
  }

  double _getHorizontalInterval() {
    final maxValue = data.map((d) => d.value).reduce((a, b) => a > b ? a : b);
    if (maxValue < 1) return 0.2;
    if (maxValue < 5) return 1;
    if (maxValue < 10) return 2;
    return 5;
  }

  String _formatBottomLabel(DateTime dt) {
    switch (period) {
      case TimePeriod.hour1:
      case TimePeriod.hours6:
        return DateFormat('HH:mm').format(dt);
      case TimePeriod.hours24:
      case TimePeriod.hours48:
        return DateFormat('HH:mm').format(dt);
      case TimePeriod.days7:
        return DateFormat('MMM d').format(dt);
      case TimePeriod.month1:
        return DateFormat('MMM d').format(dt);
    }
  }
}
