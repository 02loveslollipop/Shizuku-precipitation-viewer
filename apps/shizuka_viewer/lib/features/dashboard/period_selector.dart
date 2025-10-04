/// Period Selector Widget
/// 
/// Allows user to select time period for statistics

import 'package:flutter/material.dart';
import '../../core/providers/dashboard_provider.dart';

class PeriodSelector extends StatelessWidget {
  final TimePeriod selectedPeriod;
  final Function(TimePeriod) onPeriodChanged;

  const PeriodSelector({
    Key? key,
    required this.selectedPeriod,
    required this.onPeriodChanged,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Time Period',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: TimePeriod.values.map((period) {
                final isSelected = period == selectedPeriod;
                return ChoiceChip(
                  label: Text(period.label),
                  selected: isSelected,
                  onSelected: (_) => onPeriodChanged(period),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}
