import 'package:caliu/data/auth_api.dart';
import 'package:caliu/data/auth_session.dart';
import 'package:caliu/data/events_api.dart';
import 'package:caliu/data/favorites_api.dart';
import 'package:caliu/data/favorites_controller.dart';
import 'package:caliu/data/users_api.dart';
import 'package:caliu/follow_lists_screen.dart';
import 'package:caliu/profile_screen.dart';
import 'package:caliu/public_profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _me = PublicUser(id: 'me', username: 'jo');
const _laia = PublicUser(id: 'u1', username: 'laia_museus');
const _pau = PublicUser(id: 'u2', username: 'pau.fires');
const _marta = PublicUser(id: 'u3', username: 'marta_concerts');

/// jo → laia; laia → jo, pau; pau → laia; marta → laia. Ningú segueix marta.
MockUsersApi _api({String? currentUserId = 'me'}) => MockUsersApi(
  seed: const [_me, _laia, _pau, _marta],
  follows: const {
    'me': {'u1'},
    'u1': {'me', 'u2'},
    'u2': {'u1'},
    'u3': {'u1'},
  },
  latency: Duration.zero,
  currentUserId: currentUserId,
);

Iterable<String> _names(List<PublicUser> users) => users.map((u) => u.username);

Future<void> _pumpLists(
  WidgetTester tester,
  UsersApi api, {
  String userId = 'u1',
  FollowList initialList = FollowList.followers,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: FollowListsScreen(
        userId: userId,
        title: '@laia_museus',
        initialList: initialList,
        api: api,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _MemorySession implements AuthSessionStore {
  String? token = 'test-token';

  @override
  Future<String?> readToken() async => token;

  @override
  Future<void> saveToken(String value) async => token = value;

  @override
  Future<void> clear() async => token = null;
}

void main() {
  group('MockUsersApi seguidors i seguits', () {
    test('retorna les llistes segons el graf de seguiments', () async {
      final api = _api();
      expect(_names(await api.fetchFollowers('u1')), [
        'jo',
        'pau.fires',
        'marta_concerts',
      ]);
      expect(_names(await api.fetchFollowing('u1')), ['jo', 'pau.fires']);
      expect(await api.fetchFollowers('u3'), isEmpty);
    });

    test('la relació és unidireccional', () async {
      final api = _api();
      expect(_names(await api.fetchFollowing('u3')), ['laia_museus']);
      expect(_names(await api.fetchFollowers('u3')), isEmpty);
    });

    test('seguir algú m\'afegeix als seus seguidors', () async {
      final api = _api();
      await api.follow('u3');
      expect(_names(await api.fetchFollowers('u3')), ['jo']);
      await api.unfollow('u3');
      expect(await api.fetchFollowers('u3'), isEmpty);
    });

    test('marca a qui segueixo dins de les llistes', () async {
      final followers = await _api().fetchFollowers('u1');
      expect(followers.firstWhere((u) => u.id == 'u2').isFollowing, isFalse);
      final mine = await _api().fetchFollowing('me');
      expect(mine.single.isFollowing, isTrue);
    });

    test('un id inexistent dona 404', () async {
      await expectLater(
        _api().fetchFollowers('ningu'),
        throwsA(
          isA<UsersApiException>().having(
            (e) => e.isNotFound,
            'notFound',
            true,
          ),
        ),
      );
    });

    test('el compte propi es demana amb l\'identificador explícit', () async {
      final api = MockUsersApi(latency: Duration.zero);
      expect(_names(await api.fetchFollowing(ownProfileId)), ['laia_museus']);
      expect(_names(await api.fetchFollowers(ownProfileId)), [
        'laia_museus',
        'marta_concerts',
      ]);
    });

    test('un id desconegut és sempre un 404, també sense id propi', () async {
      // Abans, sense currentUserId, un id desconegut es tractava com el
      // compte propi (revisió de la PR #32).
      final api = MockUsersApi(latency: Duration.zero);
      for (final call in [api.fetchFollowers, api.fetchFollowing]) {
        await expectLater(
          call('id-real-del-backend'),
          throwsA(
            isA<UsersApiException>().having(
              (e) => e.isNotFound,
              'notFound',
              true,
            ),
          ),
        );
      }
    });
  });

  group('FollowListsScreen', () {
    testWidgets('mostra les dues llistes amb el seu recompte', (tester) async {
      await _pumpLists(tester, _api());

      expect(find.text('Seguidors · 3'), findsOneWidget);
      expect(find.text('Seguits · 2'), findsOneWidget);
      expect(find.byType(ListTile), findsNWidgets(3));
      expect(find.text('marta_concerts'), findsOneWidget);

      await tester.tap(find.text('Seguits · 2'));
      await tester.pumpAndSettle();
      expect(find.byType(ListTile), findsNWidgets(2));
      expect(find.text('marta_concerts'), findsNothing);
    });

    testWidgets('pot obrir-se directament a Seguits', (tester) async {
      await _pumpLists(tester, _api(), initialList: FollowList.following);
      expect(find.byType(ListTile), findsNWidgets(2));
    });

    testWidgets('sense seguidors: llista buida i recompte 0', (tester) async {
      await _pumpLists(tester, _api(), userId: 'u3');
      expect(find.text('Seguidors · 0'), findsOneWidget);
      expect(find.text('Encara no té seguidors'), findsOneWidget);
    });

    testWidgets('id inexistent: missatge d\'error', (tester) async {
      await _pumpLists(tester, _api(), userId: 'ningu');
      expect(find.text('Aquest usuari no existeix'), findsOneWidget);
    });

    testWidgets('tocar un usuari obre el seu perfil públic', (tester) async {
      await _pumpLists(tester, _api());

      await tester.tap(find.text('pau.fires'));
      await tester.pumpAndSettle();

      expect(find.byType(PublicProfileScreen), findsOneWidget);
      expect(find.text('@pau.fires'), findsOneWidget);
    });
  });

  group('Recomptes al perfil públic', () {
    testWidgets('mostra seguidors i seguits i obre les llistes', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: PublicProfileScreen(username: 'laia_museus', api: _api()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('3'), findsOneWidget);
      expect(find.text('seguidors'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('seguits'), findsOneWidget);

      await tester.tap(find.byKey(const Key('following-count')));
      await tester.pumpAndSettle();
      expect(find.byType(FollowListsScreen), findsOneWidget);
      expect(find.byType(ListTile), findsNWidgets(2));
    });

    testWidgets('seguir suma un seguidor al recompte', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: PublicProfileScreen(username: 'marta_concerts', api: _api()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('0'), findsOneWidget);

      await tester.tap(find.byKey(const Key('follow-button')));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const Key('followers-count')),
          matching: find.text('1'),
        ),
        findsOneWidget,
      );
      expect(find.text('seguidor'), findsOneWidget);
    });
  });

  testWidgets('el perfil propi obre els seus seguidors', (tester) async {
    final authApi = AuthApi(
      client: MockClient((request) async {
        if (request.url.path == '/users/me') {
          return http.Response(
            '{"id":"id-real","username":"Nuria_42","email":"nuria@example.cat",'
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
          authSession: _MemorySession(),
          eventsApi: eventsApi,
          favorites: FavoritesController(
            MockFavoritesApi(seed: const [], latency: Duration.zero),
          ),
          usersApi: MockUsersApi(latency: Duration.zero),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('my-followers')));
    await tester.pumpAndSettle();

    expect(find.text('El meu perfil'), findsOneWidget);
    expect(find.text('Seguidors · 2'), findsOneWidget);
    expect(find.text('laia_museus'), findsOneWidget);
    expect(find.text('marta_concerts'), findsOneWidget);
  });
}
