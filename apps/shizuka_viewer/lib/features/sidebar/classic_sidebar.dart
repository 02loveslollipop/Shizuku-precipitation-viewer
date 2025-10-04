/// Sidebar component for Classic Visualization
/// 
/// Displays overlay toggles, legend, and pin severity scale
/// Matches original UI design exactly

import 'package:flutter/material.dart';
import '../../localization.dart';
import '../../app_constants.dart';

class ClassicSidebar extends StatelessWidget {
  const ClassicSidebar({
    super.key,
    required this.mode,
    required this.showPins,
    required this.showHeatmap,
    required this.showContours,
    required this.onPinsChanged,
    required this.onHeatmapChanged,
    required this.onContoursChanged,
  });

  final VisualizationMode mode;
  final bool showPins;
  final bool showHeatmap;
  final bool showContours;
  final ValueChanged<bool> onPinsChanged;
  final ValueChanged<bool> onHeatmapChanged;
  final ValueChanged<bool> onContoursChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = LanguageScope.of(context);

    return Container(
      width: 260,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(right: BorderSide(color: Color(0x11000000), width: 1)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t.t('overlays.title'),
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              if (mode == VisualizationMode.realtime) ...[
                _OverlayToggle(
                  label: t.t('overlay.pins'),
                  value: showPins,
                  onChanged: onPinsChanged,
                ),
                const SizedBox(height: 24),
                Text(
                  t.t('sidebar.pinSeverity'),
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                const PinSeverityLegend(),
              ] else ...[
                _OverlayToggle(
                  label: t.t('overlay.pins'),
                  value: showPins,
                  onChanged: onPinsChanged,
                ),
                _OverlayToggle(
                  label: t.t('overlay.heatmap'),
                  value: showHeatmap,
                  onChanged: onHeatmapChanged,
                ),
                _OverlayToggle(
                  label: t.t('toggle.contours'),
                  value: showContours,
                  onChanged: onContoursChanged,
                ),
                const SizedBox(height: 24),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const IntensityLegendCard(),
                        const SizedBox(height: 24),
                        Text(
                          t.t('sidebar.pinSeverity'),
                          style: theme.textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 8),
                        const PinSeverityLegend(),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Text(
                t.t('refresh.info'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: shizukuPrimary.withOpacity(0.6),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OverlayToggle extends StatelessWidget {
  const _OverlayToggle({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return CheckboxListTile(
      value: value,
      onChanged: (checked) {
        if (checked != null) {
          onChanged(checked);
        }
      },
      dense: true,
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      title: Text(label),
    );
  }
}

class IntensityLegendCard extends StatelessWidget {
  const IntensityLegendCard({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = LanguageScope.of(context);
    final gradientStops = heatmapGradientStops();
    final gradientColors = heatmapGradientColors();
    final minValue = gradientStops.first;
    final maxValue = gradientStops.last;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t.t('precipitation.scale'),
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
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
              Text(
                '${minValue.toStringAsFixed(0)} mm',
                style: theme.textTheme.bodySmall,
              ),
              Text(
                '${maxValue.toStringAsFixed(0)}+ mm',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final cls in intensityClasses)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    margin: const EdgeInsets.only(top: 4),
                    decoration: BoxDecoration(
                      color: colorForIntensityClass(
                        cls,
                        VisualizationMode.heatmap,
                      ),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.t('intensity.${_intensityKey(cls)}.label'),
                          style: theme.textTheme.bodyMedium,
                        ),
                        Text(
                          t.t('intensity.${_intensityKey(cls)}.desc'),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: shizukuPrimary.withOpacity(0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _intensityKey(IntensityClass cls) {
    final label = cls.label.toLowerCase();
    if (label.startsWith('trace')) return 'trace';
    if (label.startsWith('light')) return 'light';
    if (label.startsWith('moderate')) return 'moderate';
    if (label.startsWith('heavy')) return 'heavy';
    if (label.startsWith('intense')) return 'intense';
    return 'violent';
  }
}

class PinSeverityLegend extends StatelessWidget {
  const PinSeverityLegend({super.key});

  @override
  Widget build(BuildContext context) {
    final t = LanguageScope.of(context);
    
    return Column(
      children: [
        _PinLegendRow(
          color: colorForPinMeasurement(pinGreenThresholdMm - 0.01),
          label: t.t('pin.low'),
          range: '0 – ${pinGreenThresholdMm.toStringAsFixed(0)} mm',
        ),
        _PinLegendRow(
          color: colorForPinMeasurement(
            (pinGreenThresholdMm + pinAmberThresholdMm) / 2,
          ),
          label: t.t('pin.moderate'),
          range:
              '${pinGreenThresholdMm.toStringAsFixed(0)} – ${pinAmberThresholdMm.toStringAsFixed(0)} mm',
        ),
        _PinLegendRow(
          color: colorForPinMeasurement(pinAmberThresholdMm + 0.01),
          label: t.t('pin.high'),
          range: '> ${pinAmberThresholdMm.toStringAsFixed(0)} mm',
        ),
      ],
    );
  }
}

class _PinLegendRow extends StatelessWidget {
  const _PinLegendRow({
    required this.color,
    required this.label,
    required this.range,
  });

  final Color color;
  final String label;
  final String range;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.bodyMedium),
                Text(
                  range,
                  style: theme.textTheme.bodySmall?.copyWith(
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
}
