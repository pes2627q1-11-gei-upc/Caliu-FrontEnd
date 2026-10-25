import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:caliu/login_screen.dart';

/// Smoke test sense Google Maps / geolocator (no disponibles al CI headless).
void main() {
  testWidgets('MaterialApp bàsic', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('Caliu'))),
    );
    expect(find.text('Caliu'), findsOneWidget);
  });

  testWidgets('login valida camps abans de cridar l’API', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(find.text('El correu electrònic és obligatori.'), findsOneWidget);
    expect(
      find.text('La contrasenya ha de tenir entre 8 i 128 caràcters.'),
      findsOneWidget,
    );
  });
}
