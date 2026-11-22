import 'dart:convert';

import 'package:caliu/data/event_query.dart';
import 'package:caliu/data/events_api.dart';
import 'package:caliu/data/search_radius.dart';
import 'package:caliu/search_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Future<void> _settleCount(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('toggle de preu envia price=free/paid i Tots l’omet (#157)', (
    tester,
  ) async {
    final requests = <Uri>[];
    final api = EventsApi(
      client: MockClient((request) async {
        requests.add(request.url);
        if (request.url.path.endsWith('/categories')) {
          return http.Response(jsonEncode({'categories': <String>[]}), 200);
        }
        if (request.url.path.endsWith('/locations')) {
          return http.Response(jsonEncode({'locations': <Object>[]}), 200);
        }
        return http.Response(
          jsonEncode({'items': <Object>[], 'total': 3, 'page': 1, 'limit': 40}),
          200,
        );
      }),
    );

    await tester.pumpWidget(MaterialApp(home: SearchScreen(api: api)));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Filtres'));
    await _settleCount(tester);

    await tester.ensureVisible(
      find.byKey(const ValueKey('price-filter-Gratuïts')),
    );
    await tester.tap(find.byKey(const ValueKey('price-filter-Gratuïts')));
    await _settleCount(tester);
    expect(
      requests.last.queryParameters['price'],
      EventPriceFilter.free,
      reason: 'el recompte provisional ha d’enviar price=free',
    );

    await tester.tap(find.text('Aplicar filtres'));
    await tester.pumpAndSettle();
    expect(
      requests.where((u) => u.queryParameters['price'] == 'free').isNotEmpty,
      isTrue,
    );

    await tester.tap(find.byTooltip('Filtres'));
    await _settleCount(tester);
    await tester.ensureVisible(
      find.byKey(const ValueKey('price-filter-De pagament')),
    );
    await tester.tap(find.byKey(const ValueKey('price-filter-De pagament')));
    await _settleCount(tester);
    expect(requests.last.queryParameters['price'], EventPriceFilter.paid);

    await tester.tap(find.byKey(const ValueKey('price-filter-Tots')));
    await _settleCount(tester);
    expect(requests.last.queryParameters.containsKey('price'), isFalse);

    await tester.tap(find.text('Aplicar filtres'));
    await tester.pumpAndSettle();
    expect(requests.last.queryParameters.containsKey('price'), isFalse);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'la creu descarta el preu provisional; Restablir tot el treu (#157)',
    (tester) async {
      final radius = SearchRadius(locate: () async => const LatLng(42, 1));
      await radius.apply(5);
      radius.updatePrice(EventPriceFilter.free);

      final requests = <Uri>[];
      final api = EventsApi(
        client: MockClient((request) async {
          requests.add(request.url);
          if (request.url.path.endsWith('/categories')) {
            return http.Response(jsonEncode({'categories': <String>[]}), 200);
          }
          if (request.url.path.endsWith('/locations')) {
            return http.Response(jsonEncode({'locations': <Object>[]}), 200);
          }
          return http.Response(
            jsonEncode({
              'items': <Object>[],
              'total': 1,
              'page': 1,
              'limit': 40,
            }),
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

      await tester.tap(find.byTooltip('Filtres'));
      await _settleCount(tester);
      await tester.ensureVisible(
        find.byKey(const ValueKey('price-filter-De pagament')),
      );
      await tester.tap(find.byKey(const ValueKey('price-filter-De pagament')));
      await _settleCount(tester);
      await tester.tap(find.byTooltip('Tancar filtres'));
      await tester.pumpAndSettle();
      expect(radius.price, EventPriceFilter.free);

      await tester.tap(find.byTooltip('Filtres'));
      await _settleCount(tester);
      await tester.tap(find.text('Restablir tot'));
      await _settleCount(tester);
      expect(requests.last.queryParameters['price'], isNull);
      expect(requests.last.queryParameters['radiusKm'], isNull);
      await tester.tap(find.text('Aplicar filtres'));
      await tester.pumpAndSettle();
      expect(radius.price, isNull);
      expect(radius.center, isNull);
      expect(radius.radiusKm, isNull);
      expect(requests.last.queryParameters.containsKey('price'), isFalse);

      await tester.pumpWidget(const SizedBox());
      radius.dispose();
    },
  );

  testWidgets('Treure radi manté el preu al recompte i a la cerca (#157)', (
    tester,
  ) async {
    final radius = SearchRadius(locate: () async => const LatLng(42, 1));
    addTearDown(radius.dispose);
    await radius.apply(5);
    radius.updatePrice(EventPriceFilter.free);

    final requests = <Uri>[];
    final api = EventsApi(
      client: MockClient((request) async {
        requests.add(request.url);
        return http.Response(
          '{"categories":[],"locations":[],"items":[],"total":1}',
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
    await tester.tap(find.byTooltip('Filtres'));
    await _settleCount(tester);
    expect(requests.last.queryParameters['radiusKm'], '5.0');

    final removeRadius = find.text('Treure radi');
    await tester.ensureVisible(removeRadius);
    await tester.tap(removeRadius);
    await _settleCount(tester);

    final preview = requests.last.queryParameters;
    expect(preview['limit'], '1');
    expect(preview['price'], EventPriceFilter.free);
    expect(preview['lat'], isNull);
    expect(preview['lng'], isNull);
    expect(preview['radiusKm'], isNull);
    expect(radius.radiusKm, 5);

    await tester.tap(find.text('Aplicar filtres'));
    await tester.pumpAndSettle();

    final search = requests.last.queryParameters;
    expect(search['limit'], '40');
    expect(search['price'], EventPriceFilter.free);
    expect(search['radiusKm'], isNull);
    expect(radius.center, isNull);
    expect(radius.radiusKm, isNull);
    expect(radius.price, EventPriceFilter.free);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('el preu es combina amb text i categoria al recompte (#157)', (
    tester,
  ) async {
    final requests = <Uri>[];
    final api = EventsApi(
      client: MockClient((request) async {
        requests.add(request.url);
        if (request.url.path.endsWith('/categories')) {
          return http.Response(
            jsonEncode({
              'categories': ['Música'],
            }),
            200,
          );
        }
        if (request.url.path.endsWith('/locations')) {
          return http.Response(jsonEncode({'locations': <Object>[]}), 200);
        }
        return http.Response(
          jsonEncode({'items': <Object>[], 'total': 2, 'page': 1, 'limit': 40}),
          200,
        );
      }),
    );

    await tester.pumpWidget(MaterialApp(home: SearchScreen(api: api)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Filtres'));
    await _settleCount(tester);

    await tester.enterText(find.byType(SearchBar).first, 'jazz');
    await _settleCount(tester);
    await tester.tap(find.text('Música'));
    await _settleCount(tester);
    await tester.ensureVisible(
      find.byKey(const ValueKey('price-filter-Gratuïts')),
    );
    await tester.tap(find.byKey(const ValueKey('price-filter-Gratuïts')));
    await _settleCount(tester);

    final preview = requests.last;
    expect(preview.queryParameters['q'], 'jazz');
    expect(preview.queryParameters['category'], 'Música');
    expect(preview.queryParameters['price'], 'free');

    await tester.tap(find.text('Aplicar filtres'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
  });
}
