import 'package:caliu/data/auth_session.dart';
import 'package:caliu/data/users_api.dart';
import 'package:caliu/public_profile_screen.dart';
import 'package:caliu/widgets/user_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _laia = PublicUser(
  id: 'u1',
  username: 'laia_museus',
  sharedEventsCount: 4,
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

class _FlakyApi implements UsersApi {
  int failures = 1;

  @override
  Future<PublicUser> fetchPublicProfile(String username) async {
    if (failures > 0) {
      failures--;
      throw const UsersApiException('Error de xarxa', statusCode: 503);
    }
    return _laia;
  }

  @override
  Future<void> follow(String userId) async {}

  @override
  Future<void> unfollow(String userId) async {}

  @override
  Future<List<PublicUser>> fetchFollowers(String userId) async => const [];

  @override
  Future<List<PublicUser>> fetchFollowing(String userId) async => const [];
}

MockUsersApi _api({AuthSessionStore? session}) =>
    MockUsersApi(seed: const [_laia], session: session, latency: Duration.zero);

Future<void> _pumpScreen(
  WidgetTester tester,
  UsersApi api, {
  String username = 'laia_museus',
  WidgetBuilder? loginBuilder,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: PublicProfileScreen(
        username: username,
        api: api,
        loginBuilder: loginBuilder,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('PublicUser.fromJson', () {
    test('llegeix el DTO públic', () {
      final user = PublicUser.fromJson({
        'id': 'u1',
        'username': 'laia_museus',
        'avatarUrl': 'https://example.cat/laia.png',
        'sharedEventsCount': 4,
      });
      expect(user.id, 'u1');
      expect(user.username, 'laia_museus');
      expect(user.avatarUrl, 'https://example.cat/laia.png');
      expect(user.sharedEventsCount, 4);
    });

    test('ignora camps privats i accepta valors absents', () {
      final user = PublicUser.fromJson({
        'id': 'u1',
        'username': 'laia_museus',
        'email': 'laia@example.cat',
        'avatarUrl': '',
      });
      expect(user.avatarUrl, isNull);
      expect(user.sharedEventsCount, 0);
    });

    test('un DTO sense id o username és un error', () {
      expect(
        () => PublicUser.fromJson({'username': 'laia'}),
        throwsA(isA<UsersApiException>()),
      );
    });
  });

  test('sharedEventsLabel en singular i plural', () {
    expect(sharedEventsLabel(0), 'Cap acte compartit');
    expect(sharedEventsLabel(1), '1 acte compartit');
    expect(sharedEventsLabel(4), '4 actes compartits');
  });

  group('MockUsersApi', () {
    test('usuari inexistent: 404', () async {
      await expectLater(
        _api().fetchPublicProfile('ningu'),
        throwsA(
          isA<UsersApiException>().having(
            (e) => e.isNotFound,
            'isNotFound',
            isTrue,
          ),
        ),
      );
    });

    test('sense sessió: 401', () async {
      await expectLater(
        _api(session: _MemorySession()).fetchPublicProfile('laia_museus'),
        throwsA(
          isA<UsersApiException>().having(
            (e) => e.isUnauthorized,
            'isUnauthorized',
            isTrue,
          ),
        ),
      );
    });
  });

  group('PublicProfileScreen', () {
    testWidgets('mostra avatar, nick i actes compartits, sense email', (
      tester,
    ) async {
      await _pumpScreen(tester, _api());

      expect(find.text('@laia_museus'), findsOneWidget);
      expect(find.text('laia_museus'), findsOneWidget);
      expect(find.text('L'), findsOneWidget);
      expect(find.text('4 actes compartits'), findsOneWidget);
      expect(find.textContaining('@example'), findsNothing);
    });

    testWidgets('usuari inexistent: missatge clar', (tester) async {
      await _pumpScreen(tester, _api(), username: 'ningu');
      expect(find.text('Aquest usuari no existeix'), findsOneWidget);
      expect(find.byIcon(Icons.person_off_outlined), findsOneWidget);
    });

    testWidgets('error de xarxa: es pot tornar a provar', (tester) async {
      await _pumpScreen(tester, _FlakyApi());
      expect(find.text('Error de xarxa'), findsOneWidget);

      await tester.tap(find.text('Tornar a provar'));
      await tester.pumpAndSettle();
      expect(find.text('4 actes compartits'), findsOneWidget);
    });

    testWidgets('sense sessió: botó per iniciar-la i carregar el perfil', (
      tester,
    ) async {
      final session = _MemorySession();
      await _pumpScreen(
        tester,
        _api(session: session),
        loginBuilder: (_) => _FakeLogin(session),
      );
      expect(
        find.text('Inicia sessió per veure perfils d\'altres usuaris'),
        findsOneWidget,
      );

      await tester.tap(find.text('Inicia sessió'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Entra'));
      await tester.pumpAndSettle();

      expect(find.text('4 actes compartits'), findsOneWidget);
    });
  });

  group('UserAvatar', () {
    testWidgets('en tocar la imatge s\'obre el perfil públic', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: UserAvatar(username: 'laia_museus', api: _api()),
            ),
          ),
        ),
      );
      expect(find.text('L'), findsOneWidget);

      await tester.tap(find.byType(UserAvatar));
      await tester.pumpAndSettle();

      expect(find.byType(PublicProfileScreen), findsOneWidget);
      expect(find.text('4 actes compartits'), findsOneWidget);
    });

    testWidgets('amb openProfileOnTap a fals no obre res', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: UserAvatar(
                username: 'laia_museus',
                openProfileOnTap: false,
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(UserAvatar));
      await tester.pumpAndSettle();
      expect(find.byType(PublicProfileScreen), findsNothing);
    });
  });
}
