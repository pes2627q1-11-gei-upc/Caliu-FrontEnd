import 'package:caliu/achievements_screen.dart';
import 'package:caliu/data/achievements_api.dart';
import 'package:caliu/data/auth_api.dart';
import 'package:caliu/data/auth_session.dart';
import 'package:caliu/data/events_api.dart';
import 'package:caliu/data/favorites_api.dart';
import 'package:caliu/data/favorites_controller.dart';
import 'package:caliu/profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _done = Achievement(
  id: 'done',
  title: 'Primeres passes',
  description: 'Assisteix al teu primer acte cultural.',
  target: 1,
  progress: 1,
  icon: 'steps',
);
const _half = Achievement(
  id: 'half',
  title: 'Explorador cultural',
  description: 'Assisteix a 5 actes culturals.',
  target: 5,
  progress: 3,
  icon: 'explore',
);
const _none = Achievement(
  id: 'none',
  title: 'Ànima social',
  description: 'Segueix 5 persones.',
  target: 5,
  icon: 'people',
);

class _MemorySession implements AuthSessionStore {
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

class _FlakyApi implements AchievementsApi {
  int failures = 1;

  @override
  Future<List<Achievement>> fetchAchievements() async {
    if (failures > 0) {
      failures--;
      throw const AchievementsApiException('Error de xarxa', statusCode: 503);
    }
    return const [_done];
  }
}

Future<void> _pump(
  WidgetTester tester,
  AchievementsApi api, {
  WidgetBuilder? loginBuilder,
}) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: AchievementsScreen(api: api, loginBuilder: loginBuilder),
    ),
  );
  await tester.pumpAndSettle();
}

MockAchievementsApi _api(List<Achievement> seed, {AuthSessionStore? session}) =>
    MockAchievementsApi(seed: seed, session: session, latency: Duration.zero);

void main() {
  group('Accés amagat fins que hi hagi progrés real (revisió PR #34)', () {
    test('per defecte, els assoliments no estan disponibles', () {
      expect(achievementsAvailable, isFalse);
    });

    testWidgets('el perfil no mostra el botó «Assoliments»', (tester) async {
      final session = _MemorySession()..token = 'test-token';
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
            authSession: session,
            eventsApi: eventsApi,
            favorites: FavoritesController(
              MockFavoritesApi(seed: const [], latency: Duration.zero),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Nuria_42'), findsOneWidget);
      expect(find.text('Assoliments'), findsNothing);
      expect(find.byKey(const Key('open-achievements')), findsNothing);
    });
  });

  group('Achievement', () {
    test('es desbloqueja en arribar al límit', () {
      expect(_done.unlocked, isTrue);
      expect(_half.unlocked, isFalse);
      expect(
        const Achievement(
          id: 'x',
          title: 'x',
          description: '',
          target: 3,
          progress: 7,
        ).unlocked,
        isTrue,
      );
    });

    test('fraction va de 0 a 1', () {
      expect(_none.fraction, 0);
      expect(_half.fraction, closeTo(0.6, 1e-9));
      expect(
        const Achievement(
          id: 'x',
          title: 'x',
          description: '',
          target: 3,
          progress: 7,
        ).fraction,
        1,
      );
    });

    test('fromJson llegeix el catàleg i valida el format', () {
      final a = Achievement.fromJson({
        'id': 'explorer',
        'title': 'Explorador cultural',
        'description': 'Assisteix a 5 actes.',
        'icon': 'explore',
        'target': 5,
        'progress': 2,
      });
      expect(a.target, 5);
      expect(a.progress, 2);
      expect(a.icon, 'explore');
      expect(
        () => Achievement.fromJson({'id': 'x', 'title': 'x'}),
        throwsA(isA<AchievementsApiException>()),
      );
    });

    test('etiqueta de progrés', () {
      expect(achievementProgressLabel(_half), '3/5');
      expect(achievementProgressLabel(_done), 'Aconseguida');
    });

    test('icones conegudes i per defecte', () {
      expect(achievementIcon('museum'), Icons.museum);
      expect(achievementIcon('desconeguda'), Icons.emoji_events);
    });
  });

  test('sense sessió, el servei dona 401', () async {
    await expectLater(
      _api(const [_done], session: _MemorySession()).fetchAchievements(),
      throwsA(
        isA<AchievementsApiException>().having(
          (e) => e.isUnauthorized,
          'isUnauthorized',
          isTrue,
        ),
      ),
    );
  });

  test('el catàleg simulat té medalles aconseguides i pendents', () {
    expect(sampleAchievements.where((a) => a.unlocked), isNotEmpty);
    expect(sampleAchievements.where((a) => !a.unlocked), isNotEmpty);
  });

  group('AchievementsScreen', () {
    testWidgets('mostra el recompte i totes les medalles amb el progrés', (
      tester,
    ) async {
      await _pump(tester, _api(const [_done, _half, _none]));

      expect(find.text('1 de 3 medalles'), findsOneWidget);
      final collection = tester.widget<LinearProgressIndicator>(
        find.byKey(const Key('collection-progress')),
      );
      expect(collection.value, closeTo(1 / 3, 1e-9));

      expect(find.text('Primeres passes'), findsOneWidget);
      expect(find.text('Explorador cultural'), findsOneWidget);
      expect(find.text('Ànima social'), findsOneWidget);
      expect(find.text('Aconseguida'), findsOneWidget);
      expect(find.text('3/5'), findsOneWidget);
      expect(find.text('0/5'), findsOneWidget);
    });

    testWidgets('les no desbloquejades surten en gris i les altres actives', (
      tester,
    ) async {
      await _pump(tester, _api(const [_done, _none]));

      final medals = tester.widgetList<CircleAvatar>(
        find.descendant(
          of: find.byType(Medal),
          matching: find.byType(CircleAvatar),
        ),
      );
      final colors = medals.map((m) => m.backgroundColor).toList();
      expect(colors[0], isNot(colors[1]));
      Finder semantics(String label) => find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == label,
      );
      expect(semantics('Medalla aconseguida'), findsOneWidget);
      expect(semantics('Medalla bloquejada'), findsOneWidget);
    });

    testWidgets('tocar una medalla mostra la regla i el progrés', (
      tester,
    ) async {
      await _pump(tester, _api(const [_half]));

      await tester.tap(find.text('Explorador cultural'));
      await tester.pumpAndSettle();

      expect(find.text('Assisteix a 5 actes culturals.'), findsOneWidget);
      expect(find.text('Progrés: 3 de 5'), findsOneWidget);
    });

    testWidgets('col·lecció completa: missatge de felicitació', (tester) async {
      await _pump(tester, _api(const [_done]));
      expect(find.text('Has completat la col·lecció!'), findsOneWidget);
    });

    testWidgets('error de xarxa: es pot tornar a provar', (tester) async {
      await _pump(tester, _FlakyApi());
      expect(find.text('Error de xarxa'), findsOneWidget);

      await tester.tap(find.text('Tornar a provar'));
      await tester.pumpAndSettle();
      expect(find.text('1 de 1 medalles'), findsOneWidget);
    });

    testWidgets('sense sessió: botó per iniciar-la i carregar', (tester) async {
      final session = _MemorySession();
      await _pump(
        tester,
        _api(const [_done, _half], session: session),
        loginBuilder: (_) => _FakeLogin(session),
      );
      expect(
        find.text('Inicia sessió per veure els teus assoliments'),
        findsOneWidget,
      );

      await tester.tap(find.text('Inicia sessió'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Entra'));
      await tester.pumpAndSettle();

      expect(find.text('1 de 2 medalles'), findsOneWidget);
    });
  });
}
