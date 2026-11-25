import 'dart:convert';

import 'package:caliu/data/auth_session.dart';
import 'package:caliu/data/event.dart';
import 'package:caliu/data/events_api.dart';
import 'package:caliu/data/favorites_api.dart';
import 'package:caliu/data/favorites_controller.dart';
import 'package:caliu/data/recommendations_api.dart';
import 'package:caliu/search_screen.dart';
import 'package:caliu/widgets/home_recommendations.dart';
import 'package:caliu/widgets/recommendation_card.dart';
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

Map<String, Object?> _event(String id, String title) => {
  'id': id,
  'title': title,
  'venue': 'Can Casacuberta',
  'municipality': 'Badalona',
  'categories': ['Música'],
  'startDate': '2026-12-04T17:30:00.000Z',
};

List<Map<String, Object?>> _events(int count) => [
  for (var i = 1; i <= count; i++) _event('evt-$i', 'Activitat $i'),
];

http.Response _page(List<Map<String, Object?>> items) => http.Response(
  jsonEncode({'items': items, 'page': 1, 'limit': 40, 'total': items.length}),
  200,
);

RecommendationsApi _api(Future<http.Response> Function(http.Request) handler) =>
    RecommendationsApi(client: MockClient(handler), baseUrl: 'http://api.test');

Future<FavoritesController> _favorites([List<Event> seed = const []]) async {
  final controller = FavoritesController(
    MockFavoritesApi(seed: seed, latency: Duration.zero),
  );
  await controller.load();
  return controller;
}

Future<void> _pumpHome(
  WidgetTester tester, {
  required RecommendationsApi api,
  required FavoritesController favorites,
  AuthSessionStore? session,
  VoidCallback? onSeeAll,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ListView(
          children: [
            HomeRecommendations(
              api: api,
              session: session ?? _Session('tok'),
              favorites: favorites,
              locate: () async => null,
              refreshDelay: Duration.zero,
              onSeeAll: onSeeAll ?? () {},
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder get _carousel => find.descendant(
  of: find.byKey(HomeRecommendations.listKey),
  matching: find.byType(Scrollable),
);

void main() {
  group('HomeRecommendations', () {
    testWidgets('mostra 6 recomanacions i acaba amb «Veure totes»', (
      tester,
    ) async {
      late http.Request seen;
      var seeAll = 0;
      await _pumpHome(
        tester,
        api: _api((request) async {
          seen = request;
          return _page(_events(10));
        }),
        favorites: await _favorites(),
        onSeeAll: () => seeAll++,
      );

      expect(seen.headers['Authorization'], 'Bearer tok');
      expect(find.text('Recomanacions'), findsOneWidget);
      expect(find.text('Activitat 1'), findsOneWidget);
      expect(find.byType(RecommendationCard), findsWidgets);

      await tester.scrollUntilVisible(
        find.byKey(HomeRecommendations.seeAllCardKey),
        300,
        scrollable: _carousel,
      );
      expect(
        find.byKey(const ValueKey('home-recommendation-evt-6')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('home-recommendation-evt-7')),
        findsNothing,
      );

      await tester.tap(find.byKey(HomeRecommendations.seeAllCardKey));
      await tester.tap(find.byKey(HomeRecommendations.seeAllKey));
      expect(seeAll, 2);
    });

    testWidgets('sense recomanacions la secció no apareix', (tester) async {
      await _pumpHome(
        tester,
        api: _api((_) async => _page([])),
        favorites: await _favorites(),
      );

      expect(find.text('Recomanacions'), findsNothing);
      expect(find.byKey(HomeRecommendations.listKey), findsNothing);
    });

    testWidgets('sense sessió no demana res ni mostra la secció', (
      tester,
    ) async {
      var calls = 0;
      await _pumpHome(
        tester,
        api: _api((_) async {
          calls++;
          return _page(_events(3));
        }),
        favorites: await _favorites(),
        session: _Session(),
      );

      expect(calls, 0);
      expect(find.text('Recomanacions'), findsNothing);
    });

    testWidgets('si falla la petició la secció no apareix', (tester) async {
      await _pumpHome(
        tester,
        api: _api((_) async => http.Response('{}', 500)),
        favorites: await _favorites(),
      );

      expect(find.text('Recomanacions'), findsNothing);
    });

    testWidgets('no mostra els preferits i s\'amaga si eren els únics', (
      tester,
    ) async {
      final favorite = Event.fromJson(_event('evt-1', 'Activitat 1'));
      await _pumpHome(
        tester,
        api: _api((_) async => _page(_events(2))),
        favorites: await _favorites([favorite]),
      );
      expect(find.text('Activitat 1'), findsNothing);
      expect(find.text('Activitat 2'), findsOneWidget);

      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('home-recommendation-evt-2')),
          matching: find.byTooltip('Afegir a preferits'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Recomanacions'), findsNothing);
    });
  });

  group('RecommendationCard', () {
    test('línia de detalls: quan · on · distància', () {
      final event = Event.fromJson({
        ..._event('evt-1', 'Vinils al capvespre'),
        'distanceMeters': 3200,
      });
      final line = RecommendationCard.detailsLine(
        event,
        DateTime(2026, 11, 25),
      );
      expect(line, contains('Can Casacuberta, Badalona'));
      expect(line, endsWith('3.2 km'));
    });
  });

  group('SearchScreen amb capçalera d\'Inici', () {
    EventsApi eventsApi() => EventsApi(
      client: MockClient((request) async {
        if (request.url.path.endsWith('/categories')) {
          return http.Response(jsonEncode({'categories': <String>[]}), 200);
        }
        return http.Response(
          jsonEncode({
            'items': [_event('r-1', 'Resultat')],
            'total': 1,
            'page': 1,
            'limit': 40,
          }),
          200,
        );
      }),
    );

    testWidgets('s\'amaga en cercar i torna en esborrar la cerca', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SearchScreen(
            api: eventsApi(),
            homeHeader: const Text('CAPÇALERA'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('CAPÇALERA'), findsOneWidget);
      expect(find.text('Resultat'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, 'teatre');
      await tester.pump();
      await tester.tap(find.text('Cercar'));
      await tester.pumpAndSettle();
      expect(find.text('CAPÇALERA'), findsNothing);
      expect(find.text('Resultat'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.clear));
      await tester.pumpAndSettle();
      expect(find.text('CAPÇALERA'), findsOneWidget);
    });

    testWidgets('un filtre de data també l\'amaga', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SearchScreen(
            api: eventsApi(),
            homeHeader: const Text('CAPÇALERA'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(ChoiceChip).first);
      await tester.pumpAndSettle();
      expect(find.text('CAPÇALERA'), findsNothing);
    });

    testWidgets('sense capçalera (cerca des del mapa) no hi ha res extra', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(home: SearchScreen(api: eventsApi())),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('search-home-body')), findsNothing);
      expect(find.text('Resultat'), findsOneWidget);
    });
  });
}
