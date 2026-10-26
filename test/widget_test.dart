import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:caliu/data/auth_api.dart';
import 'package:caliu/data/auth_session.dart';
import 'package:caliu/data/events_api.dart';
import 'package:caliu/login_screen.dart';
import 'package:caliu/profile_screen.dart';
import 'package:caliu/register_screen.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _profile = {
  'id': 'test-user-id',
  'username': 'Nuria_42',
  'email': 'nuria@example.cat',
  'preferences': <String>['Música'],
};

String _authResponse() =>
    '{"user":${_profileJson()},"token":"test-token","tokenType":"Bearer","expiresIn":3600}';

String _profileJson({String username = 'Nuria_42', List<String>? preferences}) =>
    '{"id":"test-user-id","username":"$username","email":"nuria@example.cat","preferences":${_listJson(preferences ?? ['Música'])}}';

String _listJson(List<String> values) =>
    '[${values.map((value) => '"$value"').join(',')}]';

class _MemorySession implements AuthSessionStore {
  String? token;

  @override
  Future<String?> readToken() async => token;

  @override
  Future<void> saveToken(String value) async => token = value;

  @override
  Future<void> clear() async => token = null;
}

/// Smoke test sense Google Maps / geolocator (no disponibles al CI headless).
void main() {
  testWidgets('MaterialApp bàsic', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('Caliu'))),
    );
    expect(find.text('Caliu'), findsOneWidget);
  });

  testWidgets('login valida camps abans de cridar l’API', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(find.text('El correu electrònic és obligatori.'), findsOneWidget);
    expect(find.text('La contrasenya és obligatòria.'), findsOneWidget);
  });

  testWidgets('registre correcte desa JWT i torna autenticat', (tester) async {
    final session = _MemorySession();
    final api = AuthApi(
      client: MockClient((request) async {
        expect(request.url.path, '/auth/register');
        expect(request.method, 'POST');
        return http.Response(_authResponse(), 201);
      }),
      baseUrl: 'http://localhost:3000',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => RegisterScreen(
                      authApi: api,
                      authSession: session,
                    ),
                  ),
                ),
                child: const Text('Obre registre'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Obre registre'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'Nuria_42');
    await tester.enterText(
      find.byType(TextFormField).at(1),
      'nuria@example.cat',
    );
    await tester.enterText(find.byType(TextFormField).at(2), 'Exemple42');
    await tester.enterText(find.byType(TextFormField).at(3), 'Exemple42');
    await tester.tap(find.text('Crear compte'));
    await tester.pumpAndSettle();

    expect(session.token, 'test-token');
    expect(find.text('Obre registre'), findsOneWidget);
  });

  testWidgets('login correcte guarda sessió i navega enrere', (tester) async {
    final session = _MemorySession();
    final api = AuthApi(
      client: MockClient((request) async {
        expect(request.url.path, '/auth/login');
        return http.Response(_authResponse(), 200);
      }),
      baseUrl: 'http://localhost:3000',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => LoginScreen(
                      authApi: api,
                      authSession: session,
                    ),
                  ),
                ),
                child: const Text('Obre login'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Obre login'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'nuria@example.cat');
    await tester.enterText(find.byType(TextFormField).at(1), 'Exemple42');
    await tester.tap(find.text('Inicia sessió'));
    await tester.pumpAndSettle();

    expect(session.token, 'test-token');
    expect(find.text('Obre login'), findsOneWidget);
  });

  testWidgets('perfil edita username i preferències i revoca logout', (
    tester,
  ) async {
    final session = _MemorySession()..token = 'test-token';
    var username = 'Nuria_42';
    var preferences = <String>['Música'];
    final authApi = AuthApi(
      client: MockClient((request) async {
        if (request.url.path == '/users/me' && request.method == 'GET') {
          return http.Response(
            _profileJson(username: username, preferences: preferences),
            200,
          );
        }
        if (request.url.path == '/users/me' && request.method == 'PATCH') {
          username = 'Nuria_2026';
          return http.Response(_profileJson(username: username), 200);
        }
        if (request.url.path == '/events/categories') {
          return http.Response('{"categories":["Música","Teatre"]}', 200);
        }
        if (request.url.path == '/users/me/preferences' &&
            request.method == 'GET') {
          return http.Response('{"preferences":${_listJson(preferences)}}', 200);
        }
        if (request.url.path == '/users/me/preferences' &&
            request.method == 'PUT') {
          preferences = ['Teatre'];
          return http.Response('{"preferences":["Teatre"]}', 200);
        }
        if (request.url.path == '/auth/logout') {
          return http.Response('', 204);
        }
        throw StateError('Crida inesperada: ${request.method} ${request.url}');
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
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Nuria_42'), findsOneWidget);

    await tester.tap(find.byTooltip('Edita el nom d’usuari'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Nuria_2026');
    await tester.tap(find.text('Desa'));
    await tester.pumpAndSettle();
    expect(find.text('Nuria_2026'), findsOneWidget);

    await tester.tap(find.text('Edita les preferències'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Teatre'));
    await tester.tap(find.text('Desa preferències'));
    await tester.pumpAndSettle();
    expect(find.text('Preferències: Teatre'), findsOneWidget);

    await tester.tap(find.text('Tanca la sessió'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tanca la sessió').last);
    await tester.pumpAndSettle();
    expect(session.token, isNull);
    expect(find.text('Accedeix al teu compte'), findsOneWidget);
  });

  testWidgets('un 401 en carregar perfil elimina la sessió caducada', (
    tester,
  ) async {
    final session = _MemorySession()..token = 'expired-token';
    final authApi = AuthApi(
      client: MockClient(
        (_) async => http.Response('{"error":"invalid token"}', 401),
      ),
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
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(session.token, isNull);
    expect(find.text('La sessió ha caducat. Inicia sessió de nou.'), findsOneWidget);
    expect(find.text('Accedeix al teu compte'), findsOneWidget);
  });
}
