import 'package:flutter/material.dart';

enum VisualizationMode { heatmap, contour }

const String mapboxAccessToken = String.fromEnvironment(
  'MAPBOX_ACCESS_TOKEN',
  defaultValue:
      'pk.eyJ1IjoiMDJsb3Zlc2xvbGxpcG9wIiwiYSI6ImNtZzVjZWtsdDAzOGYycXEyZGttZm85NngifQ.xkNii295tuT1s7eMs0Nrhg',
);

const String apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'https://api.shizuku.02labs.me',
);

const String blobBaseUrl = String.fromEnvironment(
  'BLOB_BASE_URL',
  defaultValue: 'https://nt9pzjxsvf6ahuq3.public.blob.vercel-storage.com',
);

const Color shizukuPrimary = Color(0xFF2D5554);
const Color shizukuSecondary = Color(0xFF93AAA9);
const Color shizukuSurface = Color(0xFFA3D5D3);
const Color shizukuBackground = Color(0xFF133332);
const Color shizukuAccent = Color(0xFF9AFFFB);

/// Thresholds (mm) that control semaphore colouring of station pins.
const double pinGreenThresholdMm = 5.0;
const double pinAmberThresholdMm = 20.0;

/// Maximum precipitation value (mm) mapped in the heat map gradient.
const double heatmapMaxValueMm = 120.0;

class IntensityClass {
  const IntensityClass({
    required this.label,
    required this.minMm,
    required this.maxMm,
    required this.description,
  });

  final String label;
  final double minMm;
  final double? maxMm;
  final String description;
}

const intensityClasses = <IntensityClass>[
  IntensityClass(
    label: 'Trace',
    minMm: 0.0,
    maxMm: 0.2,
    description: 'Trace precipitation (≤ 0.2 mm)',
  ),
  IntensityClass(
    label: 'Light',
    minMm: 0.2,
    maxMm: 2.5,
    description: 'Light precipitation (0.2 – 2.5 mm)',
  ),
  IntensityClass(
    label: 'Moderate',
    minMm: 2.5,
    maxMm: 7.6,
    description: 'Moderate precipitation (2.5 – 7.6 mm)',
  ),
  IntensityClass(
    label: 'Heavy',
    minMm: 7.6,
    maxMm: 25,
    description: 'Heavy precipitation (7.6 – 25 mm)',
  ),
  IntensityClass(
    label: 'Intense',
    minMm: 25,
    maxMm: 50,
    description: 'Intense precipitation (25 – 50 mm)',
  ),
  IntensityClass(
    label: 'Violent',
    minMm: 50,
    maxMm: null,
    description: 'Violent precipitation (> 50 mm)',
  ),
];

class _HeatmapStop {
  const _HeatmapStop(this.value, this.color);

  final double value;
  final Color color;
}

const List<_HeatmapStop> _heatmapStops = [
  _HeatmapStop(0.0, Color(0xFF0D47A1)), // deep blue
  _HeatmapStop(5.0, Color(0xFF1E88E5)), // azure blue
  _HeatmapStop(15.0, Color(0xFF26C6DA)), // cyan
  _HeatmapStop(30.0, Color(0xFF66BB6A)), // green
  _HeatmapStop(45.0, Color(0xFFFFEB3B)), // yellow
  _HeatmapStop(70.0, Color(0xFFFF8F00)), // orange
  _HeatmapStop(90.0, Color(0xFFD50000)), // red
  _HeatmapStop(heatmapMaxValueMm, Color(0xFF6A1B9A)), // purple
];

IntensityClass findIntensityClass(double value) {
  for (final cls in intensityClasses) {
    if (cls.maxMm == null) {
      if (value >= cls.minMm) return cls;
    } else if (value >= cls.minMm && value < cls.maxMm!) {
      return cls;
    }
  }
  return intensityClasses.first;
}

Color colorForIntensityClass(IntensityClass cls, VisualizationMode mode) {
  if (mode == VisualizationMode.contour) {
    final representative = cls.maxMm == null
        ? cls.minMm
        : (cls.minMm + cls.maxMm!) / 2;
    return _colorForHeatmapValue(representative);
  }
  return _colorForHeatmapValue(cls.minMm);
}

Color colorForMeasurement(double value, [VisualizationMode? _]) {
  return _colorForHeatmapValue(value);
}

Color colorForPinMeasurement(double value) {
  if (value < pinGreenThresholdMm) {
    return const Color(0xFF2E7D32); // green
  }
  if (value < pinAmberThresholdMm) {
    return const Color(0xFFF9A825); // amber
  }
  return const Color(0xFFC62828); // red
}

String pinSeverityLabel(double value) {
  if (value < pinGreenThresholdMm) {
    return 'Low';
  }
  if (value < pinAmberThresholdMm) {
    return 'Moderate';
  }
  return 'High';
}

List<Color> heatmapGradientColors() =>
    _heatmapStops.map((stop) => stop.color).toList(growable: false);

List<double> heatmapGradientStops() =>
    _heatmapStops.map((stop) => stop.value).toList(growable: false);

Color _colorForHeatmapValue(double value) {
  if (value.isNaN) {
    return Colors.transparent;
  }
  final clamped = value.clamp(0.0, heatmapMaxValueMm).toDouble();
  for (var i = 0; i < _heatmapStops.length - 1; i++) {
    final current = _heatmapStops[i];
    final next = _heatmapStops[i + 1];
    if (clamped <= next.value) {
      final range = next.value - current.value;
      if (range <= 0) {
        return next.color;
      }
      final t = (clamped - current.value) / range;
      return Color.lerp(current.color, next.color, t) ?? next.color;
    }
  }
  return _heatmapStops.last.color;
}
