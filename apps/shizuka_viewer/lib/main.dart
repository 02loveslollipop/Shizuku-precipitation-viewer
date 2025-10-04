import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import 'core/api/api_v1_client.dart';
import 'core/providers/sensor_provider.dart';
import 'core/providers/grid_provider.dart';
import 'core/providers/dashboard_provider.dart';
import 'features/visualization/visualization_screen.dart';
import 'app_theme.dart';
import 'localization.dart';

void main() {
  Intl.defaultLocale = 'en_US';
  final lang = LanguageProvider();
  
  runApp(
    LanguageScope(
      notifier: lang,
      child: ShizukuViewerApp(language: lang),
    ),
  );
}

class ShizukuViewerApp extends StatelessWidget {
  const ShizukuViewerApp({super.key, required this.language});

  final LanguageProvider language;

  @override
  Widget build(BuildContext context) {
    // Create API client instance
    // TODO: Configure with proper base URL from environment
    final apiClient = ApiV1Client(
      baseUrl: 'https://api.shizuku.02labs.me',  
    );

    return MultiProvider(
      providers: [
        // API Client (singleton)
        Provider<ApiV1Client>.value(value: apiClient),
        
        // State Providers
        ChangeNotifierProvider<SensorProvider>(
          create: (_) => SensorProvider(apiClient: apiClient),
        ),
        ChangeNotifierProvider<GridProvider>(
          create: (_) => GridProvider(apiClient: apiClient),
        ),
        ChangeNotifierProvider<DashboardProvider>(
          create: (_) => DashboardProvider(apiClient: apiClient),
        ),
      ],
      child: MaterialApp(
        title: language.t('app.title'),
        theme: buildShizukuTheme(),
        home: const VisualizationScreen(),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}
