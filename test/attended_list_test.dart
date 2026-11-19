import 'package:caliu/attended_list.dart';
import 'package:caliu/data/activity_api.dart';
import 'package:caliu/data/attended_api.dart';
import 'package:caliu/data/auth_api.dart';
import 'package:caliu/data/auth_session.dart';
import 'package:caliu/data/event.dart';
import 'package:caliu/data/events_api.dart';
import 'package:caliu/data/favorites_api.dart';
import 'package:caliu/data/favorites_controller.dart';
import 'package:caliu/profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

final _now = DateTime(2026, 11, 19, 12);

Event _event(String id, String title, DateTime start, {String? venue}) => Event(
  id: id,
  title: title,
  startDate: start,
  venue: venue,
  municipality: 'Barcelona',
);

final _concert = _event(
  'evt-1',
  'Concert al Parc',
  DateTime(2026, 11, 17),
  venue: 'Parc de la Ciutadella',
);
final _fira = _event('evt-2', 'Fira del Llibre', DateTime(2026, 4, 23));
final _grec = _event('evt-3', 'Festival Grec', DateTime(2025, 7, 10));
final _futur = _event('evt-4', 'Fira de Nadal', DateTime(2026, 12, 20));

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

class _FlakyApi implements AttendedApi {
  _FlakyApi(this.events, {this.failures = 0});

  final List<Event> events;
  int failures;

  @override
  Future<List<Event>> fetchAttended() async {
    if (failures > 0) {
      failures--;
      throw const AttendedApiException('Error de xarxa', statusCode: 503);
    }
    return events;
  }
}

MockAttendedApi _api(List<Event> seed, {AuthSessionStore? session}) =>
    MockAttendedApi(
      seed: seed,
      session: session,
      latency: Duration.zero,
      clock: () => _now,
    );

Future<void> _pump(
  WidgetTester tester,
  AttendedApi api, {
  WidgetBuilder? loginBuilder,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: AttendedList(api: api, now: _now, loginBuilder: loginBuilder),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('MockAttendedApi', () {
    test('només retorna esdeveniments passats, el més recent primer', () async {
      final events = await _api([_grec, _futur, _concert, _fira])
          .fetchAttended();
      expect(events.map((e) => e.id), ['evt-1', 'evt-2', 'evt-3']);
    });

    test('ignora esdeveniments sense data', () async {
      final events = await _api([
        const Event(id: 'x', title: 'Sense data'),
        _fira,
      ]).fetchAttended();
      expect(events.map((e) => e.id), ['evt-2']);
    });

    test('sense sessió dona 401', () async {
      await expectLater(
        _api([_fira], session: _MemorySession()).fetchAttended(),
        throwsA(
          isA<AttendedApiException>().having(
            (e) => e.isUnauthorized,
            'isUnauthorized',
            isTrue,
          ),
        ),
      );
    });

    test('les dades simulades coincideixen amb l\'activitat simulada', () {
      expect(
        sampleAttended(now: _now).map((e) => e.id),
        sampleActivity(now: _now).map((e) => e.event.id),
      );
    });
  });

  test('groupByYear agrupa per any mantenint l\'ordre', () {
    final groups = groupByYear([_concert, _fira, _grec]);
    expect(groups.keys, [2026, 2025]);
    expect(groups[2026]!.map((e) => e.id), ['evt-1', 'evt-2']);
    expect(groups[2025]!.map((e) => e.id), ['evt-3']);
  });

  group('AttendedList', () {
    testWidgets('mostra els esdeveniments passats agrupats per any', (
      tester,
    ) async {
      await _pump(tester, _api([_concert, _fira, _grec, _futur]));

      expect(find.text('2026 · 2 esdeveniments'), findsOneWidget);
      expect(find.text('2025 · 1 esdeveniment'), findsOneWidget);
      expect(find.text('Concert al Parc'), findsOneWidget);
      expect(
        find.text('fa 2 dies · Parc de la Ciutadella, Barcelona'),
        findsOneWidget,
      );
      expect(find.text('Fira de Nadal'), findsNothing);

      final header2025 = tester.getTopLeft(find.text('2025 · 1 esdeveniment'));
      final fira = tester.getTopLeft(find.text('Fira del Llibre'));
      final grec = tester.getTopLeft(find.text('Festival Grec'));
      expect(fira.dy, lessThan(header2025.dy));
      expect(header2025.dy, lessThan(grec.dy));
    });

    testWidgets('sense assistències: missatge informatiu', (tester) async {
      await _pump(tester, _api([_futur]));
      expect(
        find.text('Encara no has assistit a cap esdeveniment'),
        findsOneWidget,
      );
    });

    testWidgets('error de xarxa: es pot tornar a provar', (tester) async {
      await _pump(tester, _FlakyApi([_fira], failures: 1));
      expect(find.text('Error de xarxa'), findsOneWidget);

      await tester.tap(find.text('Tornar a provar'));
      await tester.pumpAndSettle();
      expect(find.text('Fira del Llibre'), findsOneWidget);
    });

    testWidgets('sense sessió: botó per iniciar-la i carregar', (tester) async {
      final session = _MemorySession();
      await _pump(
        tester,
        _api([_fira], session: session),
        loginBuilder: (_) => _FakeLogin(session),
      );
      expect(
        find.text('Inicia sessió per veure el teu historial'),
        findsOneWidget,
      );

      await tester.tap(find.text('Inicia sessió'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Entra'));
      await tester.pumpAndSettle();

      expect(find.text('Fira del Llibre'), findsOneWidget);
    });
  });

  testWidgets('el perfil té la pestanya Historial', (tester) async {
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
            MockFavoritesApi(seed: const [], latency: Duration.zero),
          ),
          activityApi: MockActivityApi(seed: [], latency: Duration.zero),
          attendedApi: _api([_grec]),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Historial'));
    await tester.pumpAndSettle();

    expect(find.byType(AttendedList), findsOneWidget);
    expect(find.text('Festival Grec'), findsOneWidget);
  });
}
