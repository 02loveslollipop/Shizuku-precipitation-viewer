// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

// ignore: avoid_relative_lib_imports
import '../lib/main.dart';
// ignore: avoid_relative_lib_imports
import '../lib/localization.dart';

void main() {
  testWidgets('App builds without crashing', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    final lang = LanguageProvider();
    await tester.pumpWidget(ShizukuViewerApp(language: lang));

    // Just verify that the app builds without throwing an exception
    expect(find.byType(ShizukuViewerApp), findsOneWidget);
  });
}
