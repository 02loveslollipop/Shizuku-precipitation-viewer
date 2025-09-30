import 'package:flutter/material.dart';

import '../app_constants.dart';
import '../localization.dart';
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
                LanguageScope.of(context).t('visualization.title'),
                style: theme.textTheme.titleMedium,
              ),
            ),
            RadioListTile<VisualizationMode>(
              value: VisualizationMode.heatmap,
              groupValue: mode,
              title: Text(LanguageScope.of(context).t('visualization.grid')),
              onChanged: (value) => _onSelect(context, value),
            ),
            RadioListTile<VisualizationMode>(
              value: VisualizationMode.realtime,
              groupValue: mode,
              title: Text(
                LanguageScope.of(context).t('visualization.realtime'),
              ),
              onChanged: (value) => _onSelect(context, value),
            ),
            RadioListTile<VisualizationMode>(
              value: VisualizationMode.dashboard,
              groupValue: mode,
              title: Text(
                LanguageScope.of(context).t('visualization.dashboard'),
              ),
              onChanged: (value) => _onSelect(context, value),
            ),
            const Divider(),
            if (mode != VisualizationMode.realtime)
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: Text(
                  LanguageScope.of(context).t('visualization.legend'),
                ),
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
