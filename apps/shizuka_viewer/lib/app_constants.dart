import 'package:flutter/material.dart';

enum VisualizationMode { heatmap, contour }

const String mapboxAccessToken =
    'pk.eyJ1IjoiMDJsb3Zlc2xvbGxpcG9wIiwiYSI6ImNtZzVjZWtsdDAzOGYycXEyZGttZm85NngifQ.xkNii295tuT1s7eMs0Nrhg';
const String apiBaseUrl = 'https://api.shizuku.02labs.me';

const Color shizukuPrimary = Color(0xFF2D5554);
const Color shizukuSecondary = Color(0xFF93AAA9);
const Color shizukuSurface = Color(0xFFA3D5D3);
const Color shizukuBackground = Color(0xFF133332);
const Color shizukuAccent = Color(0xFF9AFFFB);

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
    maxMm: 50,
    description: 'Heavy precipitation (7.6 – 50 mm)',
  ),
  IntensityClass(
    label: 'Violent',
    minMm: 50,
    maxMm: null,
    description: 'Violent precipitation (> 50 mm)',
  ),
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
  switch (cls.label) {
    case 'Trace':
      return mode == VisualizationMode.heatmap
          ? const Color(0xFFA3D5D3)
          : const Color(0xFF93AAA9);
    case 'Light':
      return mode == VisualizationMode.heatmap
          ? const Color(0xFF93AAA9)
          : const Color(0xFF59807E);
    case 'Moderate':
      return mode == VisualizationMode.heatmap
          ? const Color(0xFF4FC3F7)
          : const Color(0xFF2D5554);
    case 'Heavy':
      return mode == VisualizationMode.heatmap
          ? const Color(0xFFF57C00)
          : const Color(0xFFE65100);
    case 'Violent':
      return mode == VisualizationMode.heatmap
          ? const Color(0xFFC62828)
          : const Color(0xFFB71C1C);
    default:
      return shizukuPrimary;
  }
}

Color colorForMeasurement(double value, VisualizationMode mode) {
  final cls = findIntensityClass(value);
  return colorForIntensityClass(cls, mode);
}
