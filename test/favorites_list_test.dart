import 'package:caliu/data/auth_api.dart';
import 'package:caliu/data/auth_session.dart';
import 'package:caliu/data/event.dart';
import 'package:caliu/data/events_api.dart';
import 'package:caliu/data/favorites_api.dart';
import 'package:caliu/data/favorites_controller.dart';
import 'package:caliu/favorites_list.dart';
import 'package:caliu/profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _concert = Event(
  id: 'evt-1',
  title: 'Concert al Parc',
  venue: 'Parc de la Ciutadella',
  municipality: 'Barcelona',
);
const _fira = Event(id: 'evt-2', title: 'Fira del Llibre');

class _MemorySession implements AuthSessionStore {
  _MemorySession(this.token);

  String? token;

  @override
  Future<String?> readToken() async => token;

  @override
  Future<void> saveToken(String value) async => token = value;

  @override
  Future<void> clear() async => token = null;
}

FavoritesController _controller({
  List<Event> seed = const [],
  String? token = 'jwt',
}) => FavoritesController(
  MockFavoritesApi(
    session: _MemorySession(token),
    seed: seed,
    latency: Duration.zero,
  ),
);

Future<void> _pumpScreen(
  WidgetTester tester,
  FavoritesController favorites,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: FavoritesList(favorites: favorites, now: DateTime(2026, 11, 18)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('FavoritesList', () {
    testWidgets('mostra els preferits amb el lloc, el més recent primer', (
      tester,
    ) async {
      await _pumpScreen(tester, _controller(seed: const [_fira, _concert]));

      final first = tester.getTopLeft(find.text('Fira del Llibre'));
      final second = tester.getTopLeft(find.text('Concert al Parc'));
      expect(first.dy, lessThan(second.dy));
      expect(
        find.textContaining('Parc de la Ciutadella, Barcelona'),
        findsOneWidget,
      );
    });

    testWidgets('llista buida: explica com afegir preferits', (tester) async {
      await _pumpScreen(tester, _controller());

      expect(find.text('Encara no tens preferits'), findsOneWidget);
      expect(find.byIcon(Icons.favorite_border), findsOneWidget);
    });

    testWidgets('treure el cor elimina l\'esdeveniment de la llista', (
      tester,
    ) async {
      final favorites = _controller(seed: const [_concert, _fira]);
      await _pumpScreen(tester, favorites);

      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('evt-1')),
          matching: find.byTooltip('Treure de preferits'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Concert al Parc'), findsNothing);
      expect(find.text('Fira del Llibre'), findsOneWidget);
      expect(favorites.isFavorite('evt-1'), isFalse);
    });

    testWidgets('error de xarxa: missatge i botó per tornar a provar', (
      tester,
    ) async {
      final api = _FlakyApi(failures: 1, favorites: const [_concert]);
      await _pumpScreen(tester, FavoritesController(api));

      expect(find.text('Error de xarxa'), findsOneWidget);
      expect(find.byIcon(Icons.cloud_off), findsOneWidget);

      await tester.tap(find.text('Tornar a provar'));
      await tester.pumpAndSettle();
      expect(find.text('Concert al Parc'), findsOneWidget);
    });

    testWidgets('estirar cap avall recarrega la llista', (tester) async {
      final api = MockFavoritesApi(seed: const [], latency: Duration.zero);
      await _pumpScreen(tester, FavoritesController(api));
      expect(find.text('Encara no tens preferits'), findsOneWidget);

      // Afegit des d'un altre dispositiu: el servidor ja el té.
      await api.addFavorite(_concert);
      await tester.fling(
        find.text('Encara no tens preferits'),
        const Offset(0, 400),
        1000,
      );
      await tester.pumpAndSettle();

      expect(find.text('Concert al Parc'), findsOneWidget);
    });
  });

  testWidgets('el perfil mostra els preferits a la pestanya Guardats', (
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

    await tester.pumpWidget(
      MaterialApp(
        home: ProfileScreen(
          authApi: authApi,
          authSession: _MemorySession('test-token'),
          eventsApi: eventsApi,
          favorites: _controller(seed: const [_concert]),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Guardats'));
    await tester.pumpAndSettle();

    expect(find.byType(FavoritesList), findsOneWidget);
    expect(find.text('Concert al Parc'), findsOneWidget);
  });
}

/// Falla les primeres [failures] càrregues amb un error que no és 401.
class _FlakyApi implements FavoritesApi {
  _FlakyApi({required this.failures, required this.favorites});

  int failures;
  final List<Event> favorites;

  @override
  Future<List<Event>> fetchFavorites() async {
    if (failures > 0) {
      failures--;
      throw const FavoritesApiException('Error de xarxa', statusCode: 503);
    }
    return favorites;
  }

  @override
  Future<void> addFavorite(Event event) async {}

  @override
  Future<void> removeFavorite(String eventId) async {}

  @override
  Future<bool> isFavorite(String eventId) async =>
      favorites.any((e) => e.id == eventId);
}
