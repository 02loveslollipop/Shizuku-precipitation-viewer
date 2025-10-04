/// Layout Components for Classic Visualization
/// 
/// Desktop and mobile layouts with exact original styling

import 'package:flutter/material.dart';

/// Content card with rounded corners and shadow (matches original design)
class ContentCard extends StatelessWidget {
  const ContentCard({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: child,
      ),
    );
  }
}

/// Mobile sidebar overlay with backdrop
class MobileSidebarOverlay extends StatelessWidget {
  const MobileSidebarOverlay({
    super.key,
    required this.sidebar,
    required this.onClose,
  });

  final Widget sidebar;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Row(
        children: [
          SizedBox(
            width: 260,
            child: Material(
              elevation: 8,
              child: SafeArea(child: sidebar),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: onClose,
              child: Container(
                color: Colors.black.withOpacity(0.35),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Desktop layout: sidebar + content + timeline
class DesktopLayout extends StatelessWidget {
  const DesktopLayout({
    super.key,
    required this.sidebar,
    required this.content,
    this.timeline,
  });

  final Widget sidebar;
  final Widget content;
  final Widget? timeline;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        sidebar,
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                Expanded(child: ContentCard(child: content)),
                if (timeline != null) ...[
                  const SizedBox(height: 16),
                  timeline!,
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Mobile layout: content + timeline stacked
class MobileLayout extends StatelessWidget {
  const MobileLayout({
    super.key,
    required this.content,
    this.timeline,
  });

  final Widget content;
  final Widget? timeline;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          Expanded(child: ContentCard(child: content)),
          if (timeline != null) ...[
            const SizedBox(height: 16),
            timeline!,
          ],
        ],
      ),
    );
  }
}
