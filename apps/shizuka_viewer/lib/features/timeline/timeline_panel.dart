/// Timeline Panel Component
/// 
/// Displays grid timeline with slider, live/latest indicators
/// Matches original UI design exactly

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../localization.dart';
import '../../app_constants.dart';

class TimelinePanel extends StatelessWidget {
  const TimelinePanel({
    super.key,
    required this.timestamps,
    required this.activeIndex,
    required this.onIndexChanged,
  });

  final List<DateTime> timestamps;
  final int activeIndex;
  final ValueChanged<int> onIndexChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = LanguageScope.of(context);

    if (timestamps.isEmpty) {
      return Container(
        height: 160,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Center(
          child: Text(
            t.t('timeline.empty'),
            style: theme.textTheme.bodyMedium,
          ),
        ),
      );
    }

    final selectedTime = timestamps[activeIndex];
    final isLatest = activeIndex == timestamps.length - 1;
    final now = DateTime.now();
    final timeDiff = now.difference(selectedTime).abs();
    final isLive = isLatest && timeDiff.inMinutes < 10;

    final formatted = DateFormat('MMM d, HH:mm').format(selectedTime.toLocal());

    return Container(
      height: 180,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                t.t('map.timeline'),
                style: theme.textTheme.titleMedium,
              ),
              Row(
                children: [
                  if (isLive) ...[
                    const Icon(
                      Icons.wifi_tethering,
                      size: 16,
                      color: shizukuPrimary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      t.t('timeline.live'),
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(width: 12),
                  ] else if (isLatest) ...[
                    const Icon(Icons.schedule, size: 16, color: Colors.orange),
                    const SizedBox(width: 6),
                    Text(
                      t.t('timeline.latest'),
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(width: 12),
                  ],
                  Text(formatted, style: theme.textTheme.bodySmall),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Slider(
            value: activeIndex.toDouble(),
            min: 0,
            max: (timestamps.length - 1).toDouble(),
            divisions: timestamps.length > 1 ? timestamps.length - 1 : null,
            label: formatted,
            onChanged:
                timestamps.length > 1
                    ? (value) => onIndexChanged(value.round())
                    : null,
          ),
          const SizedBox(height: 8),
          Text(
            t.t('timeline.dragSlider'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: shizukuPrimary.withOpacity(0.6),
            ),
          ),
        ],
      ),
    );
  }
}
