import 'package:caliu/activity_list.dart';
import 'package:caliu/data/activity_api.dart';
import 'package:caliu/data/auth_api.dart';
import 'package:caliu/data/auth_session.dart';
import 'package:caliu/data/event.dart';
import 'package:caliu/data/events_api.dart';
import 'package:caliu/data/favorites_api.dart';
import 'package:caliu/data/favorites_controller.dart';
import 'package:caliu/favorites_screen.dart';
import 'package:caliu/profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

final _now = DateTime(2026, 11, 19, 12);

const _concert = Event(
  id: 'evt-1',
  title: 'Concert al Parc',
  venue: 'Parc de la Ciutadella',
  municipality: 'Barcelona',
);
const _fira = Event(id: 'evt-2', title: 'Fira del Llibre');

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

class _FakeLogin extends StatelessWidget {
  const _FakeLogin(this.session);

  final _MemorySession session;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: TextButton(
        onPressed: () async {
          await session.saveToken('nou-token');
          if (context.mounted) Navigator.of(context).pop(true);
        },
        child: const Text('Entra'),
      ),
    );
  }
}

/// Falla les primeres [failures] càrregues amb un error que no és 401.
class _FlakyApi implements ActivityApi {
  _FlakyApi(this.entries, {this.failures = 0});

  final List<ActivityEntry> entries;
  int failures;

  @override
  Future<List<ActivityEntry>> fetchActivity() async {
    if (failures > 0) {
      failures--;
      throw const ActivityApiException('Error de xarxa', statusCode: 503);
    }
    return entries;
  }
}

Future<void> _pump(
  WidgetTester tester,
  ActivityApi api, {
  WidgetBuilder? loginBuilder,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ActivityList(api: api, now: _now, loginBuilder: loginBuilder),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('activityWhen', () {
    test('dates relatives curtes', () {
      expect(activityWhen(DateTime(2026, 11, 19, 8), _now), 'avui');
      expect(activityWhen(DateTime(2026, 11, 18, 23), _now), 'ahir');
      expect(activityWhen(DateTime(2026, 11, 15), _now), 'fa 4 dies');
      expect(activityWhen(DateTime(2026, 11, 2), _now), '2 de nov.');
      expect(activityWhen(DateTime(2026, 10, 7), _now), '7 d\'oct.');
      expect(activityWhen(DateTime(2025, 4, 30), _now), '30 d\'abr. 2025');
    });
  });

  group('MockActivityApi', () {
    test('retorna l\'activitat de la més recent a la més antiga', () async {
      final api = MockActivityApi(
        seed: [
          ActivityEntry(
            id: 'a',
            type: ActivityType.attended,
            event: _fira,
            at: DateTime(2026, 11, 1),
          ),
          ActivityEntry(
            id: 'b',
            type: ActivityType.favoriteAdded,
            event: _concert,
            at: DateTime(2026, 11, 10),
          ),
        ],
        latency: Duration.zero,
      );
      final entries = await api.fetchActivity();
      expect(entries.map((e) => e.id), ['b', 'a']);
    });

    test('sense sessió dona 401', () async {
      final api = MockActivityApi(
        session: _MemorySession(),
        latency: Duration.zero,
      );
      await expectLater(
        api.fetchActivity(),
        throwsA(
          isA<ActivityApiException>().having(
            (e) => e.isUnauthorized,
            'isUnauthorized',
            isTrue,
          ),
        ),
      );
    });

    test('les dades simulades són recents i variades', () {
      final entries = sampleActivity(now: _now);
      expect(entries, isNotEmpty);
      expect(entries.map((e) => e.type).toSet(), ActivityType.values.toSet());
      expect(entries.every((e) => !e.at.isAfter(_now)), isTrue);
    });
  });

  group('ActivityList', () {
    testWidgets('mostra què ha fet l\'usuari, quan i on', (tester) async {
      await _pump(
        tester,
        MockActivityApi(
          seed: [
            ActivityEntry(
              id: 'a',
              type: ActivityType.favoriteAdded,
              event: _concert,
              at: DateTime(2026, 11, 19, 9),
            ),
            ActivityEntry(
              id: 'b',
              type: ActivityType.attended,
              event: _fira,
              at: DateTime(2026, 11, 18),
            ),
          ],
          latency: Duration.zero,
        ),
      );

      expect(find.text('Has afegit a preferits · avui'), findsOneWidget);
      expect(find.text('Concert al Parc'), findsOneWidget);
      expect(find.text('Parc de la Ciutadella, Barcelona'), findsOneWidget);
      expect(find.text('Has assistit a · ahir'), findsOneWidget);
      expect(find.byIcon(Icons.favorite), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
    });

    testWidgets('sense activitat: missatge explicatiu', (tester) async {
      await _pump(tester, MockActivityApi(seed: [], latency: Duration.zero));
      expect(find.text('Encara no hi ha activitat'), findsOneWidget);
    });

    testWidgets('error de xarxa: es pot tornar a provar', (tester) async {
      final api = _FlakyApi([
        ActivityEntry(
          id: 'a',
          type: ActivityType.attended,
          event: _fira,
          at: DateTime(2026, 11, 18),
        ),
      ], failures: 1);
      await _pump(tester, api);
      expect(find.text('Error de xarxa'), findsOneWidget);

      await tester.tap(find.text('Tornar a provar'));
      await tester.pumpAndSettle();
      expect(find.text('Fira del Llibre'), findsOneWidget);
    });

    testWidgets('sense sessió: botó per iniciar-la i carregar', (tester) async {
      final session = _MemorySession();
      await _pump(
        tester,
        MockActivityApi(
          session: session,
          seed: [
            ActivityEntry(
              id: 'a',
              type: ActivityType.attended,
              event: _fira,
              at: DateTime(2026, 11, 18),
            ),
          ],
          latency: Duration.zero,
        ),
        loginBuilder: (_) => _FakeLogin(session),
      );
      expect(
        find.text('Inicia sessió per veure la teva activitat'),
        findsOneWidget,
      );

      await tester.tap(find.text('Inicia sessió'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Entra'));
      await tester.pumpAndSettle();

      expect(find.text('Fira del Llibre'), findsOneWidget);
    });
  });

  testWidgets('el perfil té les pestanyes Compte, Guardats i Activitat', (
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
          favorites: FavoritesController(
            MockFavoritesApi(seed: const [_concert], latency: Duration.zero),
          ),
          activityApi: MockActivityApi(
            seed: [
              ActivityEntry(
                id: 'a',
                type: ActivityType.attended,
                event: _fira,
                at: DateTime(2026, 11, 18),
              ),
            ],
            latency: Duration.zero,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Compte (per defecte): el perfil i l'estat del servidor.
    expect(find.text('Nuria_42'), findsOneWidget);
    expect(find.text('Estat del servidor'), findsOneWidget);

    await tester.tap(find.text('Guardats'));
    await tester.pumpAndSettle();
    expect(find.byType(FavoritesList), findsOneWidget);
    expect(find.text('Concert al Parc'), findsOneWidget);

    await tester.tap(find.text('Activitat'));
    await tester.pumpAndSettle();
    expect(find.byType(ActivityList), findsOneWidget);
    expect(find.text('Fira del Llibre'), findsOneWidget);
  });
}
