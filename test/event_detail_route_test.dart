import 'dart:convert';

import 'package:caliu/event_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _launcher = MethodChannel('plugins.flutter.io/url_launcher');

Future<void> _showEvent(WidgetTester tester, Map<String, Object> fields) async {
  await http.runWithClient(
    () async {
      await tester.pumpWidget(
        const MaterialApp(home: EventDetailScreen(eventId: 'evt-1')),
      );
      await tester.pumpAndSettle();
    },
    () => MockClient(
      (_) async => http.Response(
        jsonEncode({'id': 'evt-1', 'title': 'Concert', ...fields}),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      ),
    ),
  );
}

void main() {
  testWidgets('Veure ruta obre les indicacions de l’esdeveniment', (
    tester,
  ) async {
    MethodCall? launched;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_launcher, (
      call,
    ) async {
      launched = call;
      return true;
    });
    await _showEvent(tester, {
      'location': {
        'coordinates': [2.1734, 41.3851],
      },
    });

    await tester.tap(find.text('Veure ruta'));
    await tester.pumpAndSettle();

    expect(launched?.method, 'launch');
    expect(launched?.arguments['useWebView'], isFalse);
    final uri = Uri.parse(launched!.arguments['url'] as String);
    expect(uri.path, '/maps/dir/');
    expect(uri.queryParameters['destination'], '41.3851,2.1734');
  });

  testWidgets('Veure ruta avisa quan falta la ubicació', (tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_launcher, (
      _,
    ) async {
      fail('El llançador no s’ha de cridar sense destinació');
    });
    await _showEvent(tester, {'municipality': 'Reus'});

    await tester.tap(find.text('Veure ruta'));
    await tester.pumpAndSettle();

    expect(
      find.text('La ubicació de l’esdeveniment no està disponible'),
      findsOneWidget,
    );
  });

  testWidgets('Veure ruta avisa si falla el llançador', (tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_launcher, (
      _,
    ) async {
      throw PlatformException(code: 'ACTIVITY_NOT_FOUND');
    });
    await _showEvent(tester, {
      'address': 'Carrer Major, 5',
      'municipality': 'Olot',
    });

    await tester.tap(find.text('Veure ruta'));
    await tester.pumpAndSettle();

    expect(
      find.text('No s’ha pogut obrir la ruta a Google Maps'),
      findsOneWidget,
    );
  });
}
