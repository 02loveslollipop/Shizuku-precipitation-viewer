import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../app_constants.dart';

class ShizukuAppBar extends StatelessWidget implements PreferredSizeWidget {
  const ShizukuAppBar({super.key, required this.subtitle});

  final String subtitle;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
      backgroundColor: Colors.white,
      foregroundColor: shizukuPrimary,
      elevation: 1,
    );
  }
}
