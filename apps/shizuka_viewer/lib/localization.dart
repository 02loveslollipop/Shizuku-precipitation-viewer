import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Simple front-end only localization provider.
class LanguageProvider extends ChangeNotifier {
  String _code = 'en';

  String get code => _code;

  void setLocale(String code) {
    if (_code == code) return;
    _code = code;
    notifyListeners();
  }

  String t(String key) {
    final m = _translations[_code] ?? _translations['en']!;
    return m[key] ?? _translations['en']![key] ?? key;
  }

  static const Map<String, Map<String, String>> _translations = {
    'en': {
      'app.title': 'Shizuku Viewer',
      'app.subtitle.mapViewer': 'Map viewer',
      'visualization.title': 'Visualization',
      'visualization.grid': 'Grid',
      'visualization.realtime': 'Real-time sensors',
      'visualization.dashboard': 'Dashboard & analytics',
      'visualization.legend': 'Precipitation legend',
      'overlays.title': 'Overlays',
      'overlay.pins': 'Pins',
      'overlay.heatmap': 'Heat map',
      'sidebar.pinSeverity': 'Pin severity (mm)',
      'pin.low': 'Low',
      'pin.moderate': 'Moderate',
      'pin.high': 'High',
      'refresh.info': 'Data refreshes every 2 minutes.',
      'toggle.contours': 'Contours',
      'legend.title': 'Legend',
      'precipitation.scale': 'Precipitation scale',
      'map.timeline': 'Map timeline',
      'timeline.latest': 'Latest',
      'timeline.empty': 'Timeline data is not available yet.',
      'timeline.live': 'Live',
      'timeline.dragSlider': 'Drag the slider to inspect previous grid runs.',
      'action.refresh': 'Refresh',
      'intensity.trace.label': 'Trace',
      'intensity.trace.desc': 'Trace precipitation (≤ 0.2 mm)',
      'intensity.light.label': 'Light',
      'intensity.light.desc': 'Light precipitation (0.2 – 2.5 mm)',
      'intensity.moderate.label': 'Moderate',
      'intensity.moderate.desc': 'Moderate precipitation (2.5 – 7.6 mm)',
      'intensity.heavy.label': 'Heavy',
      'intensity.heavy.desc': 'Heavy precipitation (7.6 – 25 mm)',
      'intensity.intense.label': 'Intense',
      'intensity.intense.desc': 'Intense precipitation (25 – 50 mm)',
      'intensity.violent.label': 'Violent',
      'intensity.violent.desc': 'Violent precipitation (> 50 mm)',
    },
    'es': {
      'app.title': 'Visor Shizuku',
      'app.subtitle.mapViewer': 'Visor de mapa',
      'visualization.title': 'Visualización',
      'visualization.grid': 'Cuadrícula',
      'visualization.realtime': 'Sensores en tiempo real',
      'visualization.dashboard': 'Panel y análisis',
      'visualization.legend': 'Leyenda de precipitación',
      'overlays.title': 'Superposiciones',
      'overlay.pins': 'Pines',
      'overlay.heatmap': 'Mapa de calor',
      'sidebar.pinSeverity': 'Severidad del pin (mm)',
      'pin.low': 'Bajo',
      'pin.moderate': 'Moderado',
      'pin.high': 'Alto',
      'refresh.info': 'Los datos se actualizan cada 2 minutos.',
      'toggle.contours': 'Contornos',
      'legend.title': 'Leyenda',
      'precipitation.scale': 'Escala de precipitación',
      'map.timeline': 'Línea de tiempo del mapa',
      'timeline.empty':
          'Los datos de la línea de tiempo aún no están disponibles.',
      'timeline.live': 'En directo',
      'timeline.dragSlider':
          'Arrastra el control deslizante para inspeccionar ejecuciones de cuadrícula anteriores.',
      'action.refresh': 'Actualizar',
      'intensity.trace.label': 'Trazas',
      'intensity.trace.desc': 'Trazas de precipitaciones (≤ 0.2 mm)',
      'intensity.light.label': 'Ligero',
      'intensity.light.desc': 'Precipitación ligera (0.2 – 2.5 mm)',
      'intensity.moderate.label': 'Moderado',
      'intensity.moderate.desc': 'Precipitación moderada (2.5 – 7.6 mm)',
      'intensity.heavy.label': 'Fuerte',
      'intensity.heavy.desc': 'Precipitación intensa (7.6 – 25 mm)',
      'intensity.intense.label': 'Intenso',
      'intensity.intense.desc': 'Precipitación muy intensa (25 – 50 mm)',
      'intensity.violent.label': 'Violento',
      'intensity.violent.desc': 'Precipitación violenta (> 50 mm)',
    },
    'ja': {
      'app.title': 'しずくビューア',
      'app.subtitle.mapViewer': '地図ビューア',
      'visualization.title': '視覚化',
      'visualization.grid': 'グリッド',
      'visualization.realtime': 'リアルタイムセンサー',
      'visualization.dashboard': 'ダッシュボードと分析',
      'visualization.legend': '降水量凡例',
      'overlays.title': 'オーバーレイ',
      'overlay.pins': 'ピン',
      'overlay.heatmap': 'ヒートマップ',
      'sidebar.pinSeverity': 'ピンの深刻度 (mm)',
      'pin.low': '低',
      'pin.moderate': '中',
      'pin.high': '高',
      'refresh.info': 'データは2分ごとに更新されます。',
      'toggle.contours': '等高線',
      'legend.title': '凡例',
      'precipitation.scale': '降水量スケール',
      'map.timeline': 'マップタイムライン',
      'timeline.empty': 'タイムラインデータはまだ利用できません。',
      'timeline.live': 'ライブ',
      'timeline.dragSlider': 'スライダーをドラッグして以前のグリッド実行を確認します。',
      'action.refresh': '更新',
      'intensity.trace.label': '微量',
      'intensity.trace.desc': '微量降水 (≤ 0.2 mm)',
      'intensity.light.label': '弱',
      'intensity.light.desc': '弱い降水 (0.2 – 2.5 mm)',
      'intensity.moderate.label': '中',
      'intensity.moderate.desc': '中くらいの降水 (2.5 – 7.6 mm)',
      'intensity.heavy.label': '強',
      'intensity.heavy.desc': '強い降水 (7.6 – 25 mm)',
      'intensity.intense.label': '激',
      'intensity.intense.desc': '激しい降水 (25 – 50 mm)',
      'intensity.violent.label': '猛烈',
      'intensity.violent.desc': '猛烈な降水 (> 50 mm)',
    },
  };
}

class LanguageScope extends InheritedNotifier<LanguageProvider> {
  const LanguageScope({
    required LanguageProvider super.notifier,
    required super.child,
    super.key,
  });

  static LanguageProvider of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<LanguageScope>();
    assert(scope != null, 'No LanguageScope found in context');
    return scope!.notifier!;
  }
}
