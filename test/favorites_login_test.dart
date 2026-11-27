import 'package:caliu/data/auth_api.dart';
import 'package:caliu/data/auth_session.dart';
import 'package:caliu/data/event.dart';
import 'package:caliu/data/events_api.dart';
import 'package:caliu/data/favorites_api.dart';
import 'package:caliu/data/favorites_controller.dart';
import 'package:caliu/favorites_list.dart';
import 'package:caliu/profile_screen.dart';
import 'package:caliu/widgets/favorite_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _concert = Event(id: 'evt-1', title: 'Concert al Parc');

class _MemorySession implements AuthSessionStore {
  _MemorySession([this.token]);

  String? token;

  @override
  Future<String?> readToken() async => token;

  @override
  Future<void> saveToken(String value) async => token = value;

  @override
  Future<void> clear() async => token = null;
}

/// Login fals: "Entra" desa un token i torna `true`; "Enrere" torna `false`.
class _FakeLogin extends StatelessWidget {
  const _FakeLogin(this.session);

  final _MemorySession session;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Login fals')),
      body: Column(
        children: [
          TextButton(
            onPressed: () async {
              await session.saveToken('nou-token');
              if (context.mounted) Navigator.of(context).pop(true);
            },
            child: const Text('Entra'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Enrere'),
          ),
        ],
      ),
    );
  }
}

class _Setup {
  _Setup({String? token, List<Event> serverFavorites = const []})
    : session = _MemorySession(token) {
    api = MockFavoritesApi(
      session: session,
      seed: serverFavorites,
      latency: Duration.zero,
    );
    favorites = FavoritesController(api, session: session);
  }

  final _MemorySession session;
  late final MockFavoritesApi api;
  late final FavoritesController favorites;

  Widget button() => MaterialApp(
    home: Scaffold(
      body: Center(
        child: FavoriteButton(
          event: _concert,
          controller: favorites,
          loginBuilder: (_) => _FakeLogin(session),
        ),
      ),
    ),
  );
}

Future<void> _tapHeart(WidgetTester tester) async {
  await tester.tap(find.byType(FavoriteButton));
  await tester.pumpAndSettle();
}

void main() {
  group('FavoritesController sessió', () {
    test('hasSession segons el token desat', () async {
      final session = _MemorySession();
      final controller = FavoritesController(
        MockFavoritesApi(latency: Duration.zero),
        session: session,
      );
      expect(await controller.hasSession(), isFalse);
      session.token = '';
      expect(await controller.hasSession(), isFalse);
      session.token = 'jwt';
      expect(await controller.hasSession(), isTrue);
    });

    test('sense session injectada sempre es considera que n\'hi ha', () async {
      final controller = FavoritesController(
        MockFavoritesApi(latency: Duration.zero),
      );
      expect(await controller.hasSession(), isTrue);
    });

    test('clear oblida els preferits locals', () async {
      final controller = FavoritesController(
        MockFavoritesApi(seed: const [_concert], latency: Duration.zero),
      );
      await controller.load();
      expect(controller.isFavorite('evt-1'), isTrue);

      controller.clear();
      expect(controller.isFavorite('evt-1'), isFalse);
      expect(controller.isLoaded, isFalse);
      expect(controller.favorites, isEmpty);
    });
  });

  group('FavoriteButton sense sessió', () {
    testWidgets('demana login i no marca res fins que l\'usuari decideix', (
      tester,
    ) async {
      final setup = _Setup();
      await tester.pumpWidget(setup.button());
      await _tapHeart(tester);

      expect(find.text('Guarda els teus preferits'), findsOneWidget);
      expect(find.byIcon(Icons.favorite_border), findsOneWidget);
      expect(setup.favorites.isFavorite('evt-1'), isFalse);
    });

    testWidgets('"Ara no" tanca el diàleg sense obrir el login', (
      tester,
    ) async {
      final setup = _Setup();
      await tester.pumpWidget(setup.button());
      await _tapHeart(tester);

      await tester.tap(find.text('Ara no'));
      await tester.pumpAndSettle();

      expect(find.text('Guarda els teus preferits'), findsNothing);
      expect(find.text('Login fals'), findsNothing);
      expect(setup.favorites.isFavorite('evt-1'), isFalse);
    });

    testWidgets('després d\'iniciar sessió, afegeix l\'esdeveniment', (
      tester,
    ) async {
      final setup = _Setup();
      await tester.pumpWidget(setup.button());
      await _tapHeart(tester);

      await tester.tap(find.text('Inicia sessió'));
      await tester.pumpAndSettle();
      expect(find.text('Login fals'), findsOneWidget);

      await tester.tap(find.text('Entra'));
      await tester.pumpAndSettle();

      expect(setup.favorites.isFavorite('evt-1'), isTrue);
      expect(await setup.api.isFavorite('evt-1'), isTrue);
      expect(find.byIcon(Icons.favorite), findsOneWidget);
      expect(find.text('Afegit a preferits'), findsOneWidget);
    });

    testWidgets('si el compte ja el tenia, el deixa marcat (no el treu)', (
      tester,
    ) async {
      final setup = _Setup(serverFavorites: const [_concert]);
      await tester.pumpWidget(setup.button());
      await _tapHeart(tester);
      await tester.tap(find.text('Inicia sessió'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Entra'));
      await tester.pumpAndSettle();

      expect(setup.favorites.isFavorite('evt-1'), isTrue);
      expect(await setup.api.isFavorite('evt-1'), isTrue);
    });

    testWidgets('si surt del login sense entrar, no marca res', (tester) async {
      final setup = _Setup();
      await tester.pumpWidget(setup.button());
      await _tapHeart(tester);
      await tester.tap(find.text('Inicia sessió'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Enrere'));
      await tester.pumpAndSettle();

      expect(setup.favorites.isFavorite('evt-1'), isFalse);
      expect(find.byIcon(Icons.favorite_border), findsOneWidget);
    });

    testWidgets('token caducat (401): també demana login', (tester) async {
      final setup = _Setup(token: 'caducat');
      final favorites = FavoritesController(
        _ExpiredApi(),
        session: setup.session,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FavoriteButton(
              event: _concert,
              controller: favorites,
              loginBuilder: (_) => _FakeLogin(setup.session),
            ),
          ),
        ),
      );
      await _tapHeart(tester);

      expect(find.text('Guarda els teus preferits'), findsOneWidget);
      expect(favorites.isFavorite('evt-1'), isFalse);
    });
  });

  testWidgets('pantalla de Preferits sense sessió: botó per iniciar-la', (
    tester,
  ) async {
    final setup = _Setup(serverFavorites: const [_concert]);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FavoritesList(
            favorites: setup.favorites,
            loginBuilder: (_) => _FakeLogin(setup.session),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Inicia sessió per veure els teus preferits'),
      findsOneWidget,
    );
    await tester.tap(find.text('Inicia sessió'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Entra'));
    await tester.pumpAndSettle();

    expect(find.text('Concert al Parc'), findsOneWidget);
  });

  testWidgets('tancar sessió al perfil oblida els preferits locals', (
    tester,
  ) async {
    final session = _MemorySession('test-token');
    final favorites = FavoritesController(
      MockFavoritesApi(seed: const [_concert], latency: Duration.zero),
    );
    await favorites.load();
    final authApi = AuthApi(
      client: MockClient((request) async {
        if (request.url.path == '/users/me') {
          return http.Response(
            '{"id":"u1","username":"Nuria_42","email":"nuria@example.cat",'
            '"preferences":[]}',
            200,
          );
        }
        if (request.url.path == '/auth/logout') return http.Response('', 204);
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
          authSession: session,
          eventsApi: eventsApi,
          favorites: favorites,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(favorites.isFavorite('evt-1'), isTrue);

    await tester.tap(find.text('Tanca la sessió'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tanca la sessió').last);
    await tester.pumpAndSettle();

    expect(session.token, isNull);
    expect(favorites.isFavorite('evt-1'), isFalse);
  });
}

class _ExpiredApi implements FavoritesApi {
  static const _error = FavoritesApiException('Caducat', statusCode: 401);

  @override
  Future<List<Event>> fetchFavorites() => Future.error(_error);

  @override
  Future<void> addFavorite(Event event) => Future.error(_error);

  @override
  Future<void> removeFavorite(String eventId) => Future.error(_error);

  @override
  Future<bool> isFavorite(String eventId) => Future.error(_error);
}
