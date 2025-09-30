import 'package:flutter/material.dart';

import '../app_constants.dart';

class LegendSheet extends StatelessWidget {
  const LegendSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final gradientStops = heatmapGradientStops();
    final gradientColors = heatmapGradientColors();
    final minValue = gradientStops.first;
    final maxValue = gradientStops.last;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Precipitation intensity',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
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
                Text('${minValue.toStringAsFixed(1)} mm'),
                Text('${maxValue.toStringAsFixed(0)}+ mm'),
              ],
            ),
            const SizedBox(height: 12),
            for (final cls in intensityClasses)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  radius: 10,
                  backgroundColor: colorForIntensityClass(
                    cls,
                    VisualizationMode.heatmap,
                  ),
                ),
                title: Text(cls.label),
                subtitle: Text(cls.description),
              ),
            const Divider(height: 24),
            Text(
              'Pin severity scale',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            _pinLegendRow(
              context,
              colorForPinMeasurement(pinGreenThresholdMm - 0.01),
              'Low',
              '0 – ${pinGreenThresholdMm.toStringAsFixed(0)} mm',
            ),
            _pinLegendRow(
              context,
              colorForPinMeasurement(
                (pinGreenThresholdMm + pinAmberThresholdMm) / 2,
              ),
              'Moderate',
              '${pinGreenThresholdMm.toStringAsFixed(0)} – ${pinAmberThresholdMm.toStringAsFixed(0)} mm',
            ),
            _pinLegendRow(
              context,
              colorForPinMeasurement(pinAmberThresholdMm + 0.01),
              'High',
              '> ${pinAmberThresholdMm.toStringAsFixed(0)} mm',
            ),
          ],
        ),
      ),
    );
  }
}

Widget _pinLegendRow(
  BuildContext context,
  Color color,
  String label,
  String range,
) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.bodyMedium),
              Text(
                range,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
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
