import 'dart:async';
import 'dart:convert';

import 'package:caliu/data/events_api.dart';
import 'package:caliu/data/search_radius.dart';
import 'package:caliu/search_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets('envia radi i ubicació, conserva text i permet treure el radi', (
    tester,
  ) async {
    final requests = <Uri>[];
    final radius = SearchRadius(locate: () async => const LatLng(42, 1));
    final api = EventsApi(
      client: MockClient((request) async {
        requests.add(request.url);
        return http.Response(
          jsonEncode(
            request.url.path.endsWith('categories')
                ? {
                    'categories': ['Musica'],
                  }
                : {'items': [], 'total': 0},
          ),
          200,
        );
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SearchScreen(radius: radius, api: api),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Slider), findsNothing);
    expect(find.text('RADI DE DISTÀNCIA'), findsNothing);
    await tester.enterText(find.byType(TextField).first, 'jazz');
    await tester.tap(find.text('Demà'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Filtres'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Musica'));
    await tester.enterText(
      find.widgetWithText(TextField, 'Comarca'),
      'Garrotxa',
    );
    await tester.ensureVisible(find.widgetWithText(TextField, 'Municipi'));
    await tester.enterText(find.widgetWithText(TextField, 'Municipi'), 'Olot');
    await tester.ensureVisible(find.text('Aplicar filtres'));
    await tester.tap(find.text('Aplicar filtres'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Filtres'));
    await tester.pumpAndSettle();
    expect(find.text('RADI DE DISTÀNCIA'), findsOneWidget);
    final slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.min, 0.1);
    expect(slider.max, 50);
    expect(slider.value, 5);
    tester.widget<Slider>(find.byType(Slider)).onChanged!(5);
    await tester.pump();
    expect(find.text('5,0 km'), findsOneWidget);
    await tester.ensureVisible(find.text('Aplicar radi'));
    await tester.tap(find.text('Aplicar radi'));
    await tester.pumpAndSettle();
    final query = requests.last.queryParameters;
    expect(query['q'], 'jazz');
    expect(query['lat'], '42.0');
    expect(query['lng'], '1.0');
    expect(query['radiusKm'], '5.0');
    expect(query['category'], 'Musica');
    expect(query['comarca'], 'Garrotxa');
    expect(query['municipality'], 'Olot');
    expect(query['from'], isNotNull);
    expect(query['to'], isNotNull);
    await tester.ensureVisible(find.text('Treure radi'));
    await tester.tap(find.text('Treure radi'));
    await tester.pumpAndSettle();
    expect(requests.last.queryParameters['q'], 'jazz');
    expect(requests.last.queryParameters.containsKey('lat'), isFalse);
    expect(requests.last.queryParameters.containsKey('radiusKm'), isFalse);
    for (final key in ['category', 'comarca', 'municipality', 'from', 'to']) {
      expect(requests.last.queryParameters[key], query[key]);
    }
    await tester.pumpWidget(const SizedBox());
    radius.dispose();
  });

  testWidgets('espera la ubicació i informa del timeout sense enviar radi', (
    tester,
  ) async {
    final pending = Completer<LatLng>();
    final radius = SearchRadius(locate: () => pending.future);
    final requests = <Uri>[];
    final api = EventsApi(
      client: MockClient((request) async {
        requests.add(request.url);
        return http.Response('{"items":[],"categories":[]}', 200);
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SearchScreen(radius: radius, api: api),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Filtres'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Aplicar radi'));
    await tester.tap(find.text('Aplicar radi'));
    await tester.pump();
    expect(find.text('Obtenint ubicació…'), findsOneWidget);
    expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNull);
    pending.completeError(TimeoutException('location'));
    await tester.pumpAndSettle();
    expect(find.text(SearchRadius.unavailableMessage), findsOneWidget);
    expect(
      requests.every((uri) => !uri.queryParameters.containsKey('lat')),
      isTrue,
    );
    await tester.pumpWidget(const SizedBox());
    radius.dispose();
  });

  testWidgets('Restablir tot treu el radi des del menú Filtrar', (
    tester,
  ) async {
    final radius = SearchRadius(locate: () async => const LatLng(42, 1));
    await radius.apply(5);
    final api = EventsApi(
      client: MockClient(
        (_) async => http.Response('{"items":[],"categories":[]}', 200),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SearchScreen(radius: radius, api: api),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Slider), findsNothing);
    await tester.tap(find.byTooltip('Filtres'));
    await tester.pumpAndSettle();
    expect(find.text('Radi aplicat: 5,0 km'), findsOneWidget);
    await tester.tap(find.text('Restablir tot'));
    await tester.pumpAndSettle();
    expect(radius.radiusKm, isNull);
    expect(find.text('Radi aplicat: 5,0 km'), findsNothing);
    expect(tester.widget<Slider>(find.byType(Slider)).value, 5);
    await tester.ensureVisible(find.text('Aplicar filtres'));
    await tester.tap(find.text('Aplicar filtres'));
    await tester.pumpAndSettle();
    expect(find.byType(Slider), findsNothing);
    await tester.pumpWidget(const SizedBox());
    radius.dispose();
  });

  testWidgets('un radi anterior més gran no desborda el selector de 50 km', (
    tester,
  ) async {
    final radius = SearchRadius(locate: () async => const LatLng(42, 1));
    await radius.apply(500);
    final api = EventsApi(
      client: MockClient(
        (_) async => http.Response('{"items":[],"categories":[]}', 200),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SearchScreen(radius: radius, api: api),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Filtres'));
    await tester.pumpAndSettle();
    expect(tester.widget<Slider>(find.byType(Slider)).value, 50);
    expect(find.text('Radi aplicat: 500,0 km'), findsOneWidget);
    await tester.ensureVisible(find.text('Aplicar radi'));
    await tester.tap(find.text('Aplicar radi'));
    await tester.pumpAndSettle();
    expect(radius.radiusKm, 50);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    radius.dispose();
  });
}
