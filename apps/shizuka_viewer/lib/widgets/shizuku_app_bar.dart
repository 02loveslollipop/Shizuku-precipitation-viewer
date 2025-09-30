import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../app_constants.dart';
import '../localization.dart';

class ShizukuAppBar extends StatelessWidget implements PreferredSizeWidget {
  const ShizukuAppBar({
    super.key,
    required this.subtitle,
    this.onMenuTap,
    this.mode,
    this.onModeSelected,
  });

  final String subtitle;
  final VoidCallback? onMenuTap;
  final VisualizationMode? mode;
  final ValueChanged<VisualizationMode>? onModeSelected;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lang = LanguageScope.of(context);
    return AppBar(
      leading:
          onMenuTap != null
              ? IconButton(
                icon: const Icon(Icons.menu, color: shizukuPrimary),
                onPressed: onMenuTap,
              )
              : null,
      titleSpacing: 0,
      title: Row(
        children: [
          const SizedBox(width: 8), // Add left margin
          SvgPicture.asset('assets/icons/shizuku_logo.svg', height: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  'Shizuku - $subtitle',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 16),
                if (onModeSelected != null && mode != null)
                  _ModeSelector(mode: mode!, onSelected: onModeSelected!),
              ],
            ),
          ),
        ],
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 8.0),
          child: PopupMenuButton<String>(
            tooltip: 'Language',
            icon: const Icon(Icons.translate, color: shizukuPrimary),
            onSelected: (code) {
              lang.setLocale(code);
            },
            itemBuilder:
                (ctx) => [
                  const PopupMenuItem(value: 'en', child: Text('English')),
                  const PopupMenuItem(value: 'es', child: Text('Español')),
                  const PopupMenuItem(value: 'ja', child: Text('日本語')),
                ],
          ),
        ),
      ],
      backgroundColor: Colors.white,
      foregroundColor: shizukuPrimary,
      elevation: 1,
    );
  }
}

class _ModeSelector extends StatelessWidget {
  const _ModeSelector({required this.mode, required this.onSelected});

  final VisualizationMode mode;
  final ValueChanged<VisualizationMode> onSelected;

  @override
  Widget build(BuildContext context) {
    final options = {
      VisualizationMode.heatmap: 'Grid',
      VisualizationMode.realtime: 'Real-time',
      VisualizationMode.dashboard: 'Dashboard',
    };

    return Row(
      children: options.entries
          .map((entry) {
            final isSelected = entry.key == mode;
            return Padding(
              padding: const EdgeInsets.only(left: 6.0),
              child: GestureDetector(
                onTap: () => onSelected(entry.key),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected ? shizukuBackground : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    entry.value,
                    style: TextStyle(
                      color: isSelected ? Colors.white : shizukuPrimary,
                      fontSize: 13,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
              ),
            );
          })
          .toList(growable: false),
    );
  }
}
