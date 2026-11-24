import 'dart:convert';

import 'package:caliu/data/auth_session.dart';
import 'package:caliu/data/event.dart';
import 'package:caliu/data/favorites_api.dart';
import 'package:caliu/data/favorites_controller.dart';
import 'package:caliu/data/recommendations_api.dart';
import 'package:caliu/recommendations_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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

class _BrokenSession implements AuthSessionStore {
  @override
  Future<String?> readToken() async => throw StateError('secure storage');

  @override
  Future<void> saveToken(String value) async {}

  @override
  Future<void> clear() async {}
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
    test('envia el JWT, la ubicació (4 decimals) i el límit', () async {
      late http.Request seen;
      final api = _api((request) async {
        seen = request;
        return _page([_event('evt-1', 'Concert')]);
      });

      final page = await api.fetchRecommendations(
        token: 'tok',
        lat: 41.309809974,
        lng: 2.004331106,
      );

      expect(seen.url.path, '/recommendations');
      expect(seen.headers['Authorization'], 'Bearer tok');
      expect(seen.url.queryParameters['lat'], '41.3098');
      expect(seen.url.queryParameters['lng'], '2.0043');
      expect(seen.url.queryParameters['limit'], '40');
      expect(page.items.single.title, 'Concert');
      expect(page.total, 1);
    });

    test('sense ubicació no envia lat ni lng; el límit es retalla', () async {
      late Uri seen;
      await _api((request) async {
        seen = request.url;
        return _page([]);
      }).fetchRecommendations(token: 'tok', limit: 500);

      expect(seen.queryParameters.containsKey('lat'), isFalse);
      expect(seen.queryParameters.containsKey('lng'), isFalse);
      expect(seen.queryParameters['limit'], '100');
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

    test('un 400 no mostra el missatge cru del servidor', () async {
      await expectLater(
        _api(
          (_) async => http.Response('{"error":"Paràmetre no admès: x"}', 400),
        ).fetchRecommendations(token: 'tok'),
        throwsA(
          isA<RecommendationsApiException>().having(
            (e) => e.message,
            'message',
            isNot(contains('Paràmetre')),
          ),
        ),
      );
    });

    test('JSON no vàlid i items mal formats', () async {
      await expectLater(
        _api(
          (_) async => http.Response('no és json', 200),
        ).fetchRecommendations(token: 'tok'),
        throwsA(isA<RecommendationsApiException>()),
      );

      final page = await _api(
        (_) async => http.Response(
          jsonEncode({
            'items': [
              'text',
              {'id': '', 'title': 'Sense id'},
              {'id': 'evt-1', 'title': 'Bo', 'price': 'gratis'},
              _event('evt-2', 'Concert'),
            ],
          }),
          200,
        ),
      ).fetchRecommendations(token: 'tok');
      expect(page.items.map((e) => e.id), containsAll(['evt-2']));
      expect(page.items.any((e) => e.id.isEmpty), isFalse);
    });

    test('un error de xarxa és una RecommendationsApiException', () async {
      await expectLater(
        _api(
          (_) async => throw http.ClientException('offline'),
        ).fetchRecommendations(token: 'tok'),
        throwsA(isA<RecommendationsApiException>()),
      );
    });
  });

  group('RecommendationsScreen', () {
    Future<void> pumpScreen(
      WidgetTester tester, {
      required RecommendationsApi api,
      required FavoritesController favorites,
      AuthSessionStore? session,
      bool isActive = true,
      Future<RecommendationsLocation?> Function()? locate,
      Duration refreshDelay = Duration.zero,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: RecommendationsScreen(
            api: api,
            session: session ?? _Session('tok'),
            favorites: favorites,
            locate: locate ?? () async => (lat: 41.98, lng: 2.82),
            isActive: isActive,
            refreshDelay: refreshDelay,
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
        session: _Session(),
      );

      expect(
        find.text('Inicia sessió per veure recomanacions per a tu'),
        findsOneWidget,
      );
      expect(calls, 0);
    });

    testWidgets('no carrega fins que la pestanya és visible', (tester) async {
      var calls = 0;
      final api = _api((_) async {
        calls++;
        return _page([_event('evt-1', 'Concert al Parc')]);
      });
      final favorites = await _favorites(const []);

      await pumpScreen(tester, api: api, favorites: favorites, isActive: false);
      expect(calls, 0);

      await pumpScreen(tester, api: api, favorites: favorites);
      expect(calls, 1);
      expect(find.text('Concert al Parc'), findsOneWidget);
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

    testWidgets('en marcar un preferit desapareix i es tornen a demanar (#160)', (
      tester,
    ) async {
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
      expect(requests.single.queryParameters['lat'], '41.9800');

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
    });

    testWidgets('diversos tocs seguits fan una sola recàrrega', (tester) async {
      var calls = 0;
      await pumpScreen(
        tester,
        api: _api((_) async {
          calls++;
          return _page([
            _event('evt-1', 'Concert al Parc'),
            _event('evt-3', 'Teatre de nit'),
            _event('evt-4', 'Fira de Nadal'),
          ]);
        }),
        favorites: await _favorites(const []),
        refreshDelay: const Duration(milliseconds: 600),
      );
      expect(calls, 1);

      for (final id in ['evt-1', 'evt-3']) {
        await tester.tap(
          find.descendant(
            of: find.byKey(ValueKey('recommendation-$id')),
            matching: find.byTooltip('Afegir a preferits'),
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();

      expect(calls, 2);
      expect(find.text('Fira de Nadal'), findsOneWidget);
    });

    testWidgets('un 401 tanca la sessió i demana tornar a entrar', (
      tester,
    ) async {
      final session = _Session('tok');
      await pumpScreen(
        tester,
        api: _api(
          (_) async => http.Response('{"error":"Token no vàlid"}', 401),
        ),
        favorites: await _favorites(const []),
        session: session,
      );

      expect(session.token, isNull);
      expect(
        find.text('Inicia sessió per veure recomanacions per a tu'),
        findsOneWidget,
      );
    });

    testWidgets('si falla la sessió guardada no es queda carregant', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        api: _api((_) async => _page([])),
        favorites: await _favorites(const []),
        session: _BrokenSession(),
      );

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Tornar a provar'), findsOneWidget);
    });

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

    testWidgets('una recàrrega que falla manté la llista i avisa', (
      tester,
    ) async {
      var broken = false;
      await pumpScreen(
        tester,
        api: _api(
          (_) async => broken
              ? http.Response('{"error":"boom"}', 500)
              : _page([_event('evt-1', 'Concert al Parc')]),
        ),
        favorites: await _favorites(const []),
      );

      broken = true;
      await tester.tap(find.text('Actualitzar'));
      await tester.pumpAndSettle();

      expect(find.text('Concert al Parc'), findsOneWidget);
      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('sense ubicació la petició surt sense lat ni lng', (
      tester,
    ) async {
      late Uri seen;
      await pumpScreen(
        tester,
        api: _api((request) async {
          seen = request.url;
          return _page([]);
        }),
        favorites: await _favorites(const []),
        locate: () async => null,
      );

      expect(seen.queryParameters.containsKey('lat'), isFalse);
      expect(find.text('Encara no tenim recomanacions per a tu'), findsOneWidget);
    });

    testWidgets('llista buida amb ubicació: suggereix ampliar el radi', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        api: _api((_) async => _page([])),
        favorites: await _favorites(const []),
      );

      expect(
        find.text('No hi ha recomanacions dins del teu radi d\'activitat'),
        findsOneWidget,
      );
    });
  });
}
