import 'package:flutter/material.dart';

import '../app_constants.dart';
import 'legend_sheet.dart';

class VisualizationDrawer extends StatelessWidget {
  const VisualizationDrawer({
    super.key,
    required this.mode,
    required this.onModeChanged,
  });

  final VisualizationMode mode;
  final ValueChanged<VisualizationMode> onModeChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                'Visualization',
                style: theme.textTheme.titleMedium,
              ),
            ),
            RadioListTile<VisualizationMode>(
              value: VisualizationMode.heatmap,
              groupValue: mode,
              title: const Text('Heat plot'),
              onChanged: (value) => _onSelect(context, value),
            ),
            RadioListTile<VisualizationMode>(
              value: VisualizationMode.contour,
              groupValue: mode,
              title: const Text('Contour'),
              onChanged: (value) => _onSelect(context, value),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Precipitation legend'),
              onTap: () {
                Navigator.of(context).pop();
                showModalBottomSheet(
                  context: context,
                  builder: (context) => const LegendSheet(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _onSelect(BuildContext context, VisualizationMode? value) {
    if (value == null) return;
    Navigator.of(context).pop();
    onModeChanged(value);
  }
}
