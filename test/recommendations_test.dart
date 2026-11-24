import 'dart:convert';

import 'package:caliu/data/auth_session.dart';
import 'package:caliu/data/event.dart';
import 'package:caliu/data/favorites_api.dart';
import 'package:caliu/data/favorites_controller.dart';
import 'package:caliu/data/recommendations_api.dart';
import 'package:caliu/recommendations_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _Session implements AuthSessionStore {
  _Session([this.token]);

  String? token;

  @override
  Future<String?> readToken() async => token;

  @override
  Future<void> saveToken(String value) async => token = value;

  @override
  Future<void> clear() async => token = null;
}

Map<String, Object?> _event(String id, String title) => {
  'id': id,
  'title': title,
  'municipality': 'Girona',
  'categories': ['Música'],
  'startDate': '2026-12-01T18:00:00.000Z',
  'score': 1.5,
};

http.Response _page(List<Map<String, Object?>> items) => http.Response(
  jsonEncode({'items': items, 'page': 1, 'limit': 40, 'total': items.length}),
  200,
);

RecommendationsApi _api(Future<http.Response> Function(http.Request) handler) =>
    RecommendationsApi(client: MockClient(handler), baseUrl: 'http://api.test');

Future<FavoritesController> _favorites(List<Event> seed) async {
  final controller = FavoritesController(
    MockFavoritesApi(seed: seed, latency: Duration.zero),
  );
  await controller.load();
  return controller;
}

void main() {
  group('RecommendationsApi', () {
    test('envia el JWT, la ubicació i el límit i llegeix els items', () async {
      late http.Request seen;
      final api = _api((request) async {
        seen = request;
        return _page([_event('evt-1', 'Concert')]);
      });

      final page = await api.fetchRecommendations(
        token: 'tok',
        lat: 41.98,
        lng: 2.82,
      );

      expect(seen.url.path, '/recommendations');
      expect(seen.headers['Authorization'], 'Bearer tok');
      expect(seen.url.queryParameters['lat'], '41.98');
      expect(seen.url.queryParameters['lng'], '2.82');
      expect(seen.url.queryParameters['limit'], '40');
      expect(page.items.single.title, 'Concert');
      expect(page.total, 1);
    });

    test('sense ubicació no envia lat ni lng', () async {
      late Uri seen;
      await _api((request) async {
        seen = request.url;
        return _page([]);
      }).fetchRecommendations(token: 'tok');

      expect(seen.queryParameters.containsKey('lat'), isFalse);
      expect(seen.queryParameters.containsKey('lng'), isFalse);
    });

    test('un 401 és una sessió caducada', () async {
      await expectLater(
        _api(
          (_) async => http.Response('{"error":"Token no vàlid"}', 401),
        ).fetchRecommendations(token: 'tok'),
        throwsA(
          isA<RecommendationsApiException>().having(
            (e) => e.isUnauthorized,
            'isUnauthorized',
            isTrue,
          ),
        ),
      );
    });
  });

  group('RecommendationsScreen', () {
    Future<void> pumpScreen(
      WidgetTester tester, {
      required RecommendationsApi api,
      required FavoritesController favorites,
      String? token = 'tok',
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: RecommendationsScreen(
            api: api,
            session: _Session(token),
            favorites: favorites,
            locate: () async => const LatLng(41.98, 2.82),
            refreshDelay: Duration.zero,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('sense sessió demana iniciar sessió', (tester) async {
      var calls = 0;
      await pumpScreen(
        tester,
        api: _api((_) async {
          calls++;
          return _page([]);
        }),
        favorites: await _favorites(const []),
        token: null,
      );

      expect(
        find.text('Inicia sessió per veure recomanacions per a tu'),
        findsOneWidget,
      );
      expect(calls, 0);
    });

    testWidgets('mostra les recomanacions sense els preferits', (tester) async {
      await pumpScreen(
        tester,
        api: _api(
          (_) async => _page([
            _event('evt-1', 'Concert al Parc'),
            _event('evt-2', 'Fira del Llibre'),
          ]),
        ),
        favorites: await _favorites(const [
          Event(id: 'evt-2', title: 'Fira del Llibre'),
        ]),
      );

      expect(find.text('Concert al Parc'), findsOneWidget);
      expect(find.text('Fira del Llibre'), findsNothing);
      expect(find.text('1 recomanació'), findsOneWidget);
    });

    testWidgets(
      'en marcar un preferit desapareix i es tornen a demanar (#160)',
      (tester) async {
        final requests = <Uri>[];
        await pumpScreen(
          tester,
          api: _api((request) async {
            requests.add(request.url);
            return _page([
              _event('evt-1', 'Concert al Parc'),
              _event('evt-3', 'Teatre de nit'),
            ]);
          }),
          favorites: await _favorites(const []),
        );
        expect(requests, hasLength(1));
        expect(requests.single.queryParameters['lat'], '41.98');

        await tester.tap(
          find.descendant(
            of: find.byKey(const ValueKey('recommendation-evt-1')),
            matching: find.byTooltip('Afegir a preferits'),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Concert al Parc'), findsNothing);
        expect(find.text('Teatre de nit'), findsOneWidget);
        expect(requests, hasLength(2));
      },
    );

    testWidgets('si falla, mostra l\'error i es pot tornar a provar', (
      tester,
    ) async {
      var broken = true;
      await pumpScreen(
        tester,
        api: _api(
          (_) async => broken
              ? http.Response('{"error":"boom"}', 500)
              : _page([_event('evt-1', 'Concert al Parc')]),
        ),
        favorites: await _favorites(const []),
      );

      expect(find.textContaining('No s\'han pogut carregar'), findsOneWidget);

      broken = false;
      await tester.tap(find.text('Tornar a provar'));
      await tester.pumpAndSettle();

      expect(find.text('Concert al Parc'), findsOneWidget);
    });
  });
}
