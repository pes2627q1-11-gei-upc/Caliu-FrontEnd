import 'dart:async';
import 'dart:convert';

import 'package:caliu/data/events_api.dart';
import 'package:caliu/map_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

String _page(List<Map<String, dynamic>> items) => jsonEncode({
  'items': items,
  'page': 1,
  'limit': 250,
  'total': items.length,
});

Map<String, dynamic> _item({
  required String id,
  required String title,
  required double lng,
  required double lat,
}) => {
  'id': id,
  'title': title,
  'location': {
    'type': 'Point',
    'coordinates': [lng, lat],
  },
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Completer<bool> geoReady;

  setUp(() {
    geoReady = Completer<bool>();
    const channel = MethodChannel('flutter.baseflow.com/geolocator');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'isLocationServiceEnabled':
              return geoReady.future;
            case 'checkPermission':
              return 0;
            case 'requestPermission':
              return 0;
            default:
              return null;
          }
        });
  });

  tearDown(() {
    const channel = MethodChannel('flutter.baseflow.com/geolocator');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<void> pumpMap(WidgetTester tester, EventsApi api) async {
    await tester.pumpWidget(MaterialApp(home: MapView(eventsApi: api)));
    geoReady.complete(false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets(
    'càrrega amb esdeveniments no deixa excepcions (clustering via SDK)',
    (tester) async {
      final api = EventsApi(
        client: MockClient(
          (_) async => http.Response(
            _page([
              _item(
                id: 'evt-1',
                title: 'Concert al Parc',
                lng: 2.17,
                lat: 41.39,
              ),
              _item(id: 'evt-2', title: 'Fira', lng: 2.171, lat: 41.391),
            ]),
            200,
          ),
        ),
        baseUrl: 'http://127.0.0.1:3000',
      );

      await pumpMap(tester, api);
      await tester.tap(find.byTooltip('Actualitzar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));

      // L'agrupació visual la fa l'SDK de Google (no verificable aquí).
      expect(find.byType(MapView), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('error de l’API mostra SnackBar i no petar', (tester) async {
    final api = EventsApi(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({'error': 'fallada'}),
          500,
          headers: {'content-type': 'application/json'},
        ),
      ),
      baseUrl: 'http://127.0.0.1:3000',
    );

    await pumpMap(tester, api);
    await tester.tap(find.byTooltip('Actualitzar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();

    expect(find.byType(SnackBar), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('llista buida amb notify mostra missatge', (tester) async {
    final api = EventsApi(
      client: MockClient((_) async => http.Response(_page(const []), 200)),
      baseUrl: 'http://127.0.0.1:3000',
    );

    await pumpMap(tester, api);
    await tester.tap(find.byTooltip('Actualitzar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();

    expect(
      find.text('Cap esdeveniment amb ubicació en aquest radi.'),
      findsOneWidget,
    );
  });
}
