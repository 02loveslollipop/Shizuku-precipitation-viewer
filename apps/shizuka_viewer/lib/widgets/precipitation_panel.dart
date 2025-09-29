import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api/api_client.dart';
import '../app_constants.dart';

class PrecipitationPanel extends StatelessWidget {
  const PrecipitationPanel({
    super.key,
    required this.series,
    required this.selectedIndex,
    required this.onIndexChanged,
  });

  final List<SeriesPoint> series;
  final int selectedIndex;
  final ValueChanged<int> onIndexChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final index = selectedIndex.clamp(0, series.length - 1);
    final selected = series[index];
    final dateFormatter = DateFormat('MMM d, HH:mm');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 18,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Average precipitation',
                    style: theme.textTheme.titleMedium,
                  ),
                  Text(
                    '${dateFormatter.format(selected.timestamp.toLocal())} • ${selected.value.toStringAsFixed(2)} mm',
                    style: theme.textTheme.bodySmall?.copyWith(color: shizukuPrimary.withOpacity(0.7)),
                  ),
                ],
              ),
              if (series.length > 1)
                Text(
                  '${index + 1}/${series.length}',
                  style: theme.textTheme.bodySmall?.copyWith(color: shizukuPrimary.withOpacity(0.6)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: series.isEmpty
                ? const Center(child: Text('No data'))
                : LineChart(
                    LineChartData(
                      lineTouchData: LineTouchData(enabled: false),
                      gridData: FlGridData(show: false),
                      titlesData: FlTitlesData(show: false),
                      borderData: FlBorderData(show: false),
                      lineBarsData: [
                        LineChartBarData(
                          spots: [
                            for (int i = 0; i < series.length; i++)
                              FlSpot(i.toDouble(), series[i].value)
                          ],
                          isCurved: true,
                          color: shizukuPrimary,
                          barWidth: 3,
                          dotData: FlDotData(show: false),
                          belowBarData: BarAreaData(
                            show: true,
                            color: shizukuPrimary.withOpacity(0.2),
                          ),
                        )
                      ],
                    ),
                  ),
          ),
          if (series.length > 1)
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: shizukuPrimary,
                inactiveTrackColor: shizukuPrimary.withOpacity(0.2),
                thumbColor: shizukuAccent,
                overlayColor: shizukuAccent.withOpacity(0.2),
              ),
              child: Slider(
                value: index.toDouble(),
                min: 0,
                max: (series.length - 1).toDouble(),
                divisions: series.length - 1,
                label: dateFormatter.format(selected.timestamp.toLocal()),
                onChanged: (value) => onIndexChanged(value.round()),
              ),
            )
          else
            const Text('Additional time steps unavailable yet.'),
        ],
      ),
    );
  }
}
