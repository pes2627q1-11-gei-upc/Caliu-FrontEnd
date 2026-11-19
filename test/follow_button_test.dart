import 'dart:async';

import 'package:caliu/data/auth_session.dart';
import 'package:caliu/data/users_api.dart';
import 'package:caliu/public_profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _laia = PublicUser(id: 'u1', username: 'laia_museus');
const _pau = PublicUser(id: 'u2', username: 'pau.fires', isFollowing: true);
const _jo = PublicUser(id: 'me', username: 'jo_mateix');

class _NoSession implements AuthSessionStore {
  @override
  Future<String?> readToken() async => null;

  @override
  Future<void> saveToken(String value) async {}

  @override
  Future<void> clear() async {}
}

/// Servei on cada seguiment queda pendent fins que el test el resol.
class _ControlledApi implements UsersApi {
  _ControlledApi(this.user);

  final PublicUser user;
  final List<String> log = [];
  final List<Completer<void>> calls = [];

  Future<void> _next(String entry) {
    log.add(entry);
    final completer = Completer<void>();
    calls.add(completer);
    return completer.future;
  }

  @override
  Future<PublicUser> fetchPublicProfile(String username) async => user;

  @override
  Future<void> follow(String userId) => _next('follow $userId');

  @override
  Future<void> unfollow(String userId) => _next('unfollow $userId');
}

MockUsersApi _api({String? currentUserId}) => MockUsersApi(
  seed: const [_laia, _pau, _jo],
  latency: Duration.zero,
  currentUserId: currentUserId,
);

Future<void> _pump(
  WidgetTester tester,
  UsersApi api, {
  String username = 'laia_museus',
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: PublicProfileScreen(username: username, api: api),
    ),
  );
  await tester.pumpAndSettle();
}

Finder get _button => find.byKey(const Key('follow-button'));

void main() {
  group('MockUsersApi seguiment', () {
    test('seguir i deixar de seguir canvia isFollowing', () async {
      final api = _api();
      expect((await api.fetchPublicProfile('laia_museus')).isFollowing, false);

      await api.follow('u1');
      expect((await api.fetchPublicProfile('laia_museus')).isFollowing, true);

      await api.unfollow('u1');
      expect((await api.fetchPublicProfile('laia_museus')).isFollowing, false);
    });

    test('seguir dues vegades no falla ni duplica', () async {
      final api = _api();
      await api.follow('u1');
      await api.follow('u1');
      await api.unfollow('u1');
      expect((await api.fetchPublicProfile('laia_museus')).isFollowing, false);
    });

    test('la relació és unidireccional', () async {
      final api = _api(currentUserId: 'me');
      await api.follow('u1');
      expect((await api.fetchPublicProfile('jo_mateix')).isFollowing, false);
    });

    test('no es pot seguir un mateix', () async {
      await expectLater(
        _api(currentUserId: 'me').follow('me'),
        throwsA(
          isA<UsersApiException>().having((e) => e.statusCode, 'status', 400),
        ),
      );
    });

    test('un id inexistent dona 404', () async {
      await expectLater(
        _api().follow('ningu'),
        throwsA(
          isA<UsersApiException>().having(
            (e) => e.isNotFound,
            'notFound',
            true,
          ),
        ),
      );
      await expectLater(
        _api().unfollow('ningu'),
        throwsA(isA<UsersApiException>()),
      );
    });

    test('sense sessió dona 401', () async {
      final api = MockUsersApi(
        seed: const [_laia],
        latency: Duration.zero,
        session: _NoSession(),
      );
      await expectLater(
        api.follow('u1'),
        throwsA(
          isA<UsersApiException>().having(
            (e) => e.isUnauthorized,
            'isUnauthorized',
            true,
          ),
        ),
      );
    });

    test('PublicUser.fromJson llegeix isFollowing', () {
      expect(
        PublicUser.fromJson({
          'id': 'u1',
          'username': 'laia',
          'isFollowing': true,
        }).isFollowing,
        isTrue,
      );
      expect(
        PublicUser.fromJson({'id': 'u1', 'username': 'laia'}).isFollowing,
        isFalse,
      );
    });
  });

  group('Botó Seguir', () {
    testWidgets('prémer "Seguir" el canvia a "Seguint" i ho desa', (
      tester,
    ) async {
      final api = _api();
      await _pump(tester, api);

      expect(find.text('Seguir'), findsOneWidget);
      await tester.tap(_button);
      await tester.pumpAndSettle();

      expect(find.text('Seguint'), findsOneWidget);
      expect(find.text('Ara segueixes laia_museus'), findsOneWidget);
      expect((await api.fetchPublicProfile('laia_museus')).isFollowing, true);
    });

    testWidgets('si ja el segueix, surt "Seguint" i es pot deixar de seguir', (
      tester,
    ) async {
      final api = _api();
      await _pump(tester, api, username: 'pau.fires');

      expect(find.text('Seguint'), findsOneWidget);
      await tester.tap(_button);
      await tester.pumpAndSettle();

      expect(find.text('Seguir'), findsOneWidget);
      expect(find.text('Has deixat de seguir pau.fires'), findsOneWidget);
      expect((await api.fetchPublicProfile('pau.fires')).isFollowing, false);
    });

    testWidgets('canvi optimista i botó desactivat mentre es desa', (
      tester,
    ) async {
      final api = _ControlledApi(_laia);
      await _pump(tester, api);

      await tester.tap(_button);
      await tester.pump();
      expect(find.text('Seguint'), findsOneWidget);
      expect(
        tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNull,
      );

      await tester.tap(_button, warnIfMissed: false);
      expect(api.log, ['follow u1']);

      api.calls.single.complete();
      await tester.pumpAndSettle();
      expect(
        tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNotNull,
      );
    });

    testWidgets('si falla, torna a "Seguir" i explica l\'error', (
      tester,
    ) async {
      final api = _ControlledApi(_laia);
      await _pump(tester, api);

      await tester.tap(_button);
      await tester.pump();
      api.calls.single.completeError(
        const UsersApiException('Error de xarxa', statusCode: 503),
      );
      await tester.pumpAndSettle();

      expect(find.text('Seguir'), findsOneWidget);
      expect(find.text('Error de xarxa'), findsOneWidget);
    });

    testWidgets('al propi perfil, seguir-se mostra l\'error del servidor', (
      tester,
    ) async {
      await _pump(tester, _api(currentUserId: 'me'), username: 'jo_mateix');

      await tester.tap(_button);
      await tester.pumpAndSettle();

      expect(find.text('Seguir'), findsOneWidget);
      expect(find.text('No et pots seguir a tu mateix'), findsOneWidget);
    });
  });
}
