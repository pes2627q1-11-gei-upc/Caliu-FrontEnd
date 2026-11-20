import 'dart:async';

import 'package:caliu/data/auth_api.dart';
import 'package:caliu/data/auth_session.dart';
import 'package:caliu/data/event.dart';
import 'package:caliu/data/favorite_alerts_api.dart';
import 'package:caliu/data/favorite_alerts_controller.dart';
import 'package:caliu/data/favorites_api.dart';
import 'package:caliu/data/events_api.dart';
import 'package:caliu/data/favorites_controller.dart';
import 'package:caliu/favorites_list.dart';
import 'package:caliu/profile_screen.dart';
import 'package:caliu/widgets/alerts_toggle_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _concert = Event(id: 'evt-1', title: 'Concert al Parc');
const _fira = Event(id: 'evt-2', title: 'Fira del Llibre');

/// Sessió sense token, per provar el 401.
class _MemorySession implements AuthSessionStore {
  String? token;

  @override
  Future<String?> readToken() async => token;

  @override
  Future<void> saveToken(String value) async => token = value;

  @override
  Future<void> clear() async => token = null;
}

/// Servei on cada canvi queda pendent fins que el test el resol.
class _ControlledAlertsApi implements FavoriteAlertsApi {
  final List<String> log = [];
  final List<Completer<void>> calls = [];

  @override
  Future<Set<String>> fetchMuted() async => {};

  @override
  Future<void> setAlertsEnabled(String eventId, {required bool enabled}) {
    log.add('${enabled ? 'on' : 'off'} $eventId');
    final completer = Completer<void>();
    calls.add(completer);
    return completer.future;
  }
}

MockFavoriteAlertsApi _alertsApi({Set<String>? muted}) =>
    MockFavoriteAlertsApi(muted: muted, latency: Duration.zero);

Future<FavoritesController> _favorites(List<Event> events) async {
  final controller = FavoritesController(
    MockFavoritesApi(seed: events, latency: Duration.zero),
  );
  await controller.load();
  return controller;
}

Widget _button(
  FavoriteAlertsController alerts,
  FavoritesController favorites, {
  Event event = _concert,
}) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: AlertsToggleButton(
        event: event,
        alerts: alerts,
        favorites: favorites,
      ),
    ),
  ),
);

class _TokenSession implements AuthSessionStore {
  String? token = 'test-token';

  @override
  Future<String?> readToken() async => token;

  @override
  Future<void> saveToken(String value) async => token = value;

  @override
  Future<void> clear() async => token = null;
}

void main() {
  group('Campana amagada fins que hi hagi notificacions (revisió PR #29)', () {
    test('per defecte, les alertes no estan disponibles', () {
      expect(favoriteAlertsAvailable, isFalse);
    });

    testWidgets('la pestanya Guardats del perfil no mostra la campana', (
      tester,
    ) async {
      final authApi = AuthApi(
        client: MockClient((request) async {
          if (request.url.path == '/users/me') {
            return http.Response(
              '{"id":"u1","username":"Nuria_42","email":"nuria@example.cat",'
              '"preferences":[]}',
              200,
            );
          }
          throw StateError('Crida inesperada: ${request.url}');
        }),
        baseUrl: 'http://localhost:3000',
      );
      final eventsApi = EventsApi(
        client: MockClient(
          (_) async => http.Response('{"status":"ok","service":"test"}', 200),
        ),
        baseUrl: 'http://localhost:3000',
      );
      final alerts = FavoriteAlertsController(_alertsApi());

      await tester.pumpWidget(
        MaterialApp(
          home: ProfileScreen(
            authApi: authApi,
            authSession: _TokenSession(),
            eventsApi: eventsApi,
            favorites: await _favorites(const [_concert]),
            alerts: alerts,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guardats'));
      await tester.pumpAndSettle();

      expect(find.text('Concert al Parc'), findsOneWidget);
      expect(find.byType(AlertsToggleButton), findsNothing);
    });
  });

  group('FavoriteAlertsController', () {
    test('per defecte les alertes estan actives', () {
      final alerts = FavoriteAlertsController(_alertsApi());
      expect(alerts.alertsEnabled('evt-1'), isTrue);
    });

    test('load llegeix quins preferits estan silenciats', () async {
      final alerts = FavoriteAlertsController(_alertsApi(muted: {'evt-1'}));
      await alerts.load();
      expect(alerts.alertsEnabled('evt-1'), isFalse);
      expect(alerts.alertsEnabled('evt-2'), isTrue);
    });

    test('toggle és optimista i es desa al servidor', () async {
      final api = _alertsApi();
      final alerts = FavoriteAlertsController(api);

      final pending = alerts.toggle('evt-1');
      expect(alerts.alertsEnabled('evt-1'), isFalse);
      expect(await pending, isFalse);
      expect(await api.fetchMuted(), {'evt-1'});

      expect(await alerts.toggle('evt-1'), isTrue);
      expect(await api.fetchMuted(), isEmpty);
    });

    test('si falla, desfà el canvi i rellança l\'error', () async {
      final api = _ControlledAlertsApi();
      final alerts = FavoriteAlertsController(api);

      final pending = alerts.toggle('evt-1');
      expect(alerts.alertsEnabled('evt-1'), isFalse);
      api.calls.single.completeError(
        const FavoritesApiException('Error de xarxa'),
      );
      await expectLater(pending, throwsA(isA<FavoritesApiException>()));
      expect(alerts.alertsEnabled('evt-1'), isTrue);
    });

    test('ignora tocs repetits mentre hi ha una petició en curs', () async {
      final api = _ControlledAlertsApi();
      final alerts = FavoriteAlertsController(api);

      final first = alerts.toggle('evt-1');
      expect(await alerts.toggle('evt-1'), isFalse);
      expect(api.log, ['off evt-1']);

      api.calls.single.complete();
      await first;
    });

    test('clear torna a deixar totes les alertes actives', () async {
      final alerts = FavoriteAlertsController(_alertsApi(muted: {'evt-1'}));
      await alerts.load();
      alerts.clear();
      expect(alerts.alertsEnabled('evt-1'), isTrue);
    });

    test('sense sessió el servei dona 401 i load no falla', () async {
      final api = MockFavoriteAlertsApi(
        session: _MemorySession(),
        latency: Duration.zero,
      );
      await expectLater(
        api.setAlertsEnabled('evt-1', enabled: false),
        throwsA(
          isA<FavoritesApiException>().having(
            (e) => e.isUnauthorized,
            'isUnauthorized',
            isTrue,
          ),
        ),
      );
      final alerts = FavoriteAlertsController(api);
      await alerts.load();
      expect(alerts.alertsEnabled('evt-1'), isTrue);
    });
  });

  group('AlertsToggleButton', () {
    testWidgets('no es mostra si l\'esdeveniment no és un preferit', (
      tester,
    ) async {
      final favorites = await _favorites(const []);
      await tester.pumpWidget(
        _button(FavoriteAlertsController(_alertsApi()), favorites),
      );
      expect(find.byType(IconButton), findsNothing);
    });

    testWidgets('silenciar canvia la campana, avisa i el deixa guardat', (
      tester,
    ) async {
      final favorites = await _favorites(const [_concert]);
      final alerts = FavoriteAlertsController(_alertsApi());
      await tester.pumpWidget(_button(alerts, favorites));

      expect(find.byTooltip('Silenciar alertes'), findsOneWidget);
      await tester.tap(find.byType(AlertsToggleButton));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.notifications_off_outlined), findsOneWidget);
      expect(find.byTooltip('Activar alertes'), findsOneWidget);
      expect(
        find.text('Alertes silenciades per a "Concert al Parc"'),
        findsOneWidget,
      );
      expect(favorites.isFavorite('evt-1'), isTrue);

      await tester.tap(find.byType(AlertsToggleButton));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.notifications_active_outlined), findsOneWidget);
      expect(
        find.text('Alertes activades per a "Concert al Parc"'),
        findsOneWidget,
      );
    });

    testWidgets('si falla, torna enrere i l\'error substitueix l\'avís', (
      tester,
    ) async {
      final favorites = await _favorites(const [_concert]);
      final api = _ControlledAlertsApi();
      await tester.pumpWidget(
        _button(FavoriteAlertsController(api), favorites),
      );

      await tester.tap(find.byType(AlertsToggleButton));
      await tester.pump();
      expect(find.byIcon(Icons.notifications_off_outlined), findsOneWidget);

      api.calls.single.completeError(
        const FavoritesApiException('Error de xarxa', statusCode: 503),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.notifications_active_outlined), findsOneWidget);
      expect(find.text('Error de xarxa'), findsOneWidget);
      expect(find.textContaining('Alertes silenciades'), findsNothing);
    });
  });

  group('Alertes a Guardats', () {
    Future<void> pumpList(
      WidgetTester tester,
      FavoritesController favorites,
      FavoriteAlertsController alerts,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FavoritesList(favorites: favorites, alerts: alerts),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Finder bell(String id, IconData icon) => find.descendant(
      of: find.byKey(ValueKey(id)),
      matching: find.byIcon(icon),
    );

    testWidgets('silenciar un preferit no afecta els altres', (tester) async {
      final favorites = await _favorites(const [_concert, _fira]);
      final alerts = FavoriteAlertsController(_alertsApi());
      await pumpList(tester, favorites, alerts);

      expect(find.byType(AlertsToggleButton), findsNWidgets(2));
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('evt-1')),
          matching: find.byTooltip('Silenciar alertes'),
        ),
      );
      await tester.pumpAndSettle();

      expect(bell('evt-1', Icons.notifications_off_outlined), findsOneWidget);
      expect(
        bell('evt-2', Icons.notifications_active_outlined),
        findsOneWidget,
      );
      expect(find.text('Concert al Parc'), findsOneWidget);
    });

    testWidgets('el canvi es manté en tornar a obrir la pantalla', (
      tester,
    ) async {
      final api = _alertsApi();
      final favoritesApi = MockFavoritesApi(
        seed: const [_concert],
        latency: Duration.zero,
      );
      await pumpList(
        tester,
        FavoritesController(favoritesApi),
        FavoriteAlertsController(api),
      );
      await tester.tap(find.byTooltip('Silenciar alertes'));
      await tester.pumpAndSettle();

      // Pantalla nova, controladors nous: l'estat ve del servidor.
      await tester.pumpWidget(const SizedBox());
      await pumpList(
        tester,
        FavoritesController(favoritesApi),
        FavoriteAlertsController(api),
      );

      expect(bell('evt-1', Icons.notifications_off_outlined), findsOneWidget);
    });

    testWidgets('sense controlador d\'alertes no es mostra la campana', (
      tester,
    ) async {
      final favorites = await _favorites(const [_concert]);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: FavoritesList(favorites: favorites)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AlertsToggleButton), findsNothing);
    });
  });
}
