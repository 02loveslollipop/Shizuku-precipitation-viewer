import 'package:flutter/material.dart';

import '../app_constants.dart';

class LegendSheet extends StatelessWidget {
  const LegendSheet({super.key});

  @override
  Widget build(BuildContext context) {
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
            for (final cls in intensityClasses)
              ListTile(
                dense: true,
                leading: CircleAvatar(
                  radius: 8,
                  backgroundColor: colorForIntensityClass(cls, VisualizationMode.heatmap),
                ),
                title: Text(cls.label),
                subtitle: Text(cls.description),
              ),
          ],
        ),
      ),
    );
  }
}
