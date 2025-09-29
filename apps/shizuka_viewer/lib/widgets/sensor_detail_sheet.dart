import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api/api_client.dart';
import '../app_constants.dart';

class SensorDetailSheet extends StatelessWidget {
  const SensorDetailSheet({super.key, required this.measurement, required this.history});

  final SensorMeasurement measurement;
  final List<SeriesPoint> history;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final intensity = findIntensityClass(measurement.valueMm);
    final formatter = DateFormat('MMM d, HH:mm');

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            measurement.name ?? measurement.sensorId,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text('Location: ${measurement.lat.toStringAsFixed(4)}, ${measurement.lon.toStringAsFixed(4)}'),
          const Text('Address: Mocked via Mapbox (todo)'),
          Text('Measurement: ${measurement.valueMm.toStringAsFixed(2)} mm'),
          Text('Intensity: ${intensity.label}'),
          Text('Timestamp: ${formatter.format(measurement.timestamp.toLocal())}'),
          const SizedBox(height: 12),
          if (history.isEmpty)
            const Text('No historical data available.')
          else
            SizedBox(
              height: 180,
              child: LineChart(
                LineChartData(
                  lineTouchData: LineTouchData(enabled: false),
                  gridData: FlGridData(show: false),
                  titlesData: FlTitlesData(show: false),
                  borderData: FlBorderData(show: false),
                  lineBarsData: [
                    LineChartBarData(
                      spots: [
                        for (int i = 0; i < history.length; i++)
                          FlSpot(i.toDouble(), history[i].value)
                      ],
                      isCurved: true,
                      color: shizukuPrimary,
                      barWidth: 2,
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
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          )
        ],
      ),
    );
  }
}
