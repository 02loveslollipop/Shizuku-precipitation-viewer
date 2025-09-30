import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../app_constants.dart';
import '../localization.dart';

class ShizukuAppBar extends StatelessWidget implements PreferredSizeWidget {
  const ShizukuAppBar({super.key, required this.subtitle});

  final String subtitle;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lang = LanguageScope.of(context);
    return AppBar(
      titleSpacing: 0,
      title: Row(
        children: [
          const SizedBox(width: 8), // Add left margin
          SvgPicture.asset('assets/icons/shizuku_logo.svg', height: 32),
          const SizedBox(width: 12),
          Text(
            'Shizuku - $subtitle',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
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
