/// Map Controls Widget
/// 
/// Provides common map control buttons (zoom, fit bounds, etc.)

import 'package:flutter/material.dart';

class MapControls extends StatelessWidget {
  final VoidCallback? onZoomIn;
  final VoidCallback? onZoomOut;
  final VoidCallback? onResetView;
  final VoidCallback? onLocate;

  const MapControls({
    Key? key,
    this.onZoomIn,
    this.onZoomOut,
    this.onResetView,
    this.onLocate,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (onZoomIn != null)
          _ControlButton(
            icon: Icons.add,
            onPressed: onZoomIn!,
            tooltip: 'Zoom In',
          ),
        const SizedBox(height: 8),
        if (onZoomOut != null)
          _ControlButton(
            icon: Icons.remove,
            onPressed: onZoomOut!,
            tooltip: 'Zoom Out',
          ),
        const SizedBox(height: 8),
        if (onResetView != null)
          _ControlButton(
            icon: Icons.fit_screen,
            onPressed: onResetView!,
            tooltip: 'Reset View',
          ),
        if (onLocate != null) ...[
          const SizedBox(height: 8),
          _ControlButton(
            icon: Icons.my_location,
            onPressed: onLocate!,
            tooltip: 'My Location',
          ),
        ],
      ],
    );
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final String tooltip;

  const _ControlButton({
    Key? key,
    required this.icon,
    required this.onPressed,
    required this.tooltip,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        elevation: 2,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 20),
          ),
        ),
      ),
    );
  }
}
