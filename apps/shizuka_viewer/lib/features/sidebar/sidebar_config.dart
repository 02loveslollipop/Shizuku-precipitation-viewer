/// Sidebar Option and Section Models

import 'package:flutter/material.dart';

enum SidebarOptionType {
  toggle,
  radio,
  action,
  custom,
}

class SidebarOption {
  final String id;
  final String label;
  final IconData icon;
  final SidebarOptionType type;
  final bool? value;  // For toggles
  final List<String>? radioOptions;  // For radio groups
  final int? selectedRadioIndex;
  final VoidCallback? onTap;  // For actions
  final Widget? customWidget;  // For custom content
  final ValueChanged<bool>? onToggleChanged;  // Callback for toggles
  final ValueChanged<int>? onRadioChanged;  // Callback for radio options

  SidebarOption({
    required this.id,
    required this.label,
    required this.icon,
    required this.type,
    this.value,
    this.radioOptions,
    this.selectedRadioIndex,
    this.onTap,
    this.customWidget,
    this.onToggleChanged,
    this.onRadioChanged,
  });
}

class SidebarSection {
  final String title;
  final List<SidebarOption> options;

  SidebarSection({
    required this.title,
    required this.options,
  });
}
