/// Modular Sidebar Widget

import 'package:flutter/material.dart';
import 'sidebar_config.dart';

class ModularSidebar extends StatelessWidget {
  final List<SidebarSection> sections;
  final Function(String optionId, dynamic value)? onOptionChanged;
  final double? width;
  final Color? backgroundColor;

  const ModularSidebar({
    Key? key,
    required this.sections,
    this.onOptionChanged,
    this.width = 320,
    this.backgroundColor,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: backgroundColor ?? Theme.of(context).cardColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(2, 0),
          ),
        ],
      ),
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: sections.length,
        separatorBuilder: (context, index) => const Divider(height: 32),
        itemBuilder: (context, index) {
          return _SidebarSectionWidget(
            section: sections[index],
            onOptionChanged: onOptionChanged,
          );
        },
      ),
    );
  }
}

class _SidebarSectionWidget extends StatelessWidget {
  final SidebarSection section;
  final Function(String optionId, dynamic value)? onOptionChanged;

  const _SidebarSectionWidget({
    Key? key,
    required this.section,
    this.onOptionChanged,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          section.title,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        ...section.options.map((option) => _SidebarOptionWidget(
          option: option,
          onChanged: (value) => onOptionChanged?.call(option.id, value),
        )),
      ],
    );
  }
}

class _SidebarOptionWidget extends StatelessWidget {
  final SidebarOption option;
  final Function(dynamic value)? onChanged;

  const _SidebarOptionWidget({
    Key? key,
    required this.option,
    this.onChanged,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    switch (option.type) {
      case SidebarOptionType.toggle:
        return SwitchListTile(
          title: Text(option.label),
          secondary: Icon(option.icon),
          value: option.value ?? false,
          onChanged: (val) => onChanged?.call(val),
        );
      case SidebarOptionType.radio:
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
                onChanged: (val) => onChanged?.call(val),
                secondary: Icon(option.icon),
                dense: true,
                selected: selected,
              );
            }),
          ],
        );
      case SidebarOptionType.action:
        return ListTile(
          title: Text(option.label),
          leading: Icon(option.icon),
          onTap: option.onTap,
        );
      case SidebarOptionType.custom:
        return option.customWidget ?? const SizedBox();
    }
  }
}
