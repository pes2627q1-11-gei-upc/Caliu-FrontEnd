import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Smoke test sense Google Maps / geolocator (no disponibles al CI headless).
void main() {
  testWidgets('MaterialApp bàsic', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Text('Caliu')),
      ),
    );
    expect(find.text('Caliu'), findsOneWidget);
  });
}
