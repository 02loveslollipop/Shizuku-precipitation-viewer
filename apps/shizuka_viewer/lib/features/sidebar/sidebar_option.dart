/// Individual Sidebar Option Widgets
/// Used for custom option types if needed.

import 'package:flutter/material.dart';
import 'sidebar_config.dart';

class SidebarToggleOption extends StatelessWidget {
  final SidebarOption option;
  final ValueChanged<bool> onChanged;

  const SidebarToggleOption({
    Key? key,
    required this.option,
    required this.onChanged,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      title: Text(option.label),
      secondary: Icon(option.icon),
      value: option.value ?? false,
      onChanged: onChanged,
    );
  }
}

class SidebarRadioOption extends StatelessWidget {
  final SidebarOption option;
  final ValueChanged<int> onChanged;

  const SidebarRadioOption({
    Key? key,
    required this.option,
    required this.onChanged,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(option.label, style: Theme.of(context).textTheme.bodyMedium),
        ...List.generate(option.radioOptions?.length ?? 0, (i) {
          final selected = option.selectedRadioIndex == i;
          return RadioListTile<int>(
            title: Text(option.radioOptions![i]),
            value: i,
            groupValue: option.selectedRadioIndex,
            onChanged: (val) => val != null ? onChanged(val) : null,
            secondary: Icon(option.icon),
            dense: true,
            selected: selected,
          );
        }),
      ],
    );
  }
}
