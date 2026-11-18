import 'dart:async';

import 'package:caliu/data/events_api.dart';
import 'package:caliu/data/search_radius.dart';
import 'package:caliu/map_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets(
    'mapa manté el centre i radi en actualitzar i els treu en restablir',
    (tester) async {
      // Manté pendent l'arrencada del mapa natiu: es prova el contracte HTTP
      // de MapView sense un SDK de Google ni GPS real al runner de tests.
      const channel = MethodChannel('flutter.baseflow.com/geolocator');
      final service = Completer<bool>();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (_) => service.future,
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        );
      });
      final radius = SearchRadius(locate: () async => const LatLng(42, 1));
      final requests = <Uri>[];
      final api = EventsApi(
        client: MockClient((request) async {
          requests.add(request.url);
          return http.Response('{"items":[]}', 200);
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: MapView(radius: radius, eventsApi: api),
        ),
      );
      await radius.apply(5);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(requests.last.queryParameters['lat'], '42.0');
      expect(requests.last.queryParameters['lng'], '1.0');
      expect(requests.last.queryParameters['radiusKm'], '5.0');

      await tester.tap(find.byTooltip('Actualitzar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(requests.last.queryParameters['lat'], '42.0');
      expect(requests.last.queryParameters['radiusKm'], '5.0');

      radius.clear();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(requests.last.queryParameters['radiusKm'], isNot('5.0'));
      expect(requests.last.queryParameters['lat'], isNot('42.0'));
      await tester.pumpWidget(const SizedBox());
      service.complete(false);
      await tester.pumpAndSettle();
      radius.dispose();
      expect(tester.takeException(), isNull);
    },
  );
}
