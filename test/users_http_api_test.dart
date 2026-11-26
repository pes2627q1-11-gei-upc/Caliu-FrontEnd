import 'dart:convert';

import 'package:caliu/data/auth_session.dart';
import 'package:caliu/data/users_api.dart';
import 'package:caliu/data/users_http_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _baseUrl = 'http://127.0.0.1:3000';
const _laiaId = '6710f1c2a1b2c3d4e5f60718';
const _meId = '6710f1c2a1b2c3d4e5f60799';

class _MemorySession implements AuthSessionStore {
  _MemorySession([this.token = 'jwt-prova']);

  String? token;

  @override
  Future<String?> readToken() async => token;

  @override
  Future<void> saveToken(String value) async => token = value;

  @override
  Future<void> clear() async => token = null;
}

(HttpUsersApi, List<http.Request>) _api(
  Future<http.Response> Function(http.Request request) handler, {
  AuthSessionStore? session,
}) {
  final requests = <http.Request>[];
  final api = HttpUsersApi(
    client: MockClient((request) {
      requests.add(request);
      return handler(request);
    }),
    baseUrl: _baseUrl,
    session: session ?? _MemorySession(),
  );
  return (api, requests);
}

Matcher _error({int? status, Object? message}) => throwsA(
  isA<UsersApiException>()
      .having((e) => e.statusCode, 'statusCode', status)
      .having((e) => e.message, 'message', message ?? isA<String>()),
);

String _list(List<Map<String, String>> items) =>
    jsonEncode({'items': items, 'total': items.length});

void main() {
  group('Perfil públic', () {
    test('GET /users/{username} amb el token', () async {
      final (api, requests) = _api(
        (_) async => http.Response(
          jsonEncode({
            'id': _laiaId,
            'username': 'laia_museus',
            'avatarUrl': 'https://cdn.example.cat/laia.jpg',
            'sharedEventsCount': 4,
            'isFollowing': true,
          }),
          200,
        ),
      );

      final user = await api.fetchPublicProfile('laia_museus');

      expect(user.id, _laiaId);
      expect(user.username, 'laia_museus');
      expect(user.avatarUrl, 'https://cdn.example.cat/laia.jpg');
      expect(user.sharedEventsCount, 4);
      expect(user.isFollowing, isTrue);
      expect(requests.single.url.path, '/users/laia_museus');
      expect(requests.single.headers['authorization'], 'Bearer jwt-prova');
    });

    test('codifica el nom a la ruta', () async {
      final (api, requests) = _api(
        (_) async => http.Response(
          jsonEncode({
            'id': _laiaId,
            'username': 'Núria',
            'avatarUrl': null,
            'sharedEventsCount': 0,
            'isFollowing': false,
          }),
          200,
        ),
      );
      final user = await api.fetchPublicProfile('Núria');
      expect(user.avatarUrl, isNull);
      expect(requests.single.url.toString(), '$_baseUrl/users/N%C3%BAria');
    });

    test('una foto amb ruta relativa es completa amb el servidor', () async {
      final (api, _) = _api(
        (_) async => http.Response(
          jsonEncode({
            'id': _laiaId,
            'username': 'laia',
            'avatarUrl': '/users/$_laiaId/avatar/3',
            'sharedEventsCount': 0,
            'isFollowing': false,
          }),
          200,
        ),
      );
      expect(
        (await api.fetchPublicProfile('laia')).avatarUrl,
        '$_baseUrl/users/$_laiaId/avatar/3',
      );
    });

    for (final status in [400, 404]) {
      test('$status: l\'usuari no existeix', () async {
        final (api, _) = _api((_) async => http.Response('', status));
        await expectLater(
          api.fetchPublicProfile('ningu'),
          _error(status: 404, message: 'Aquest usuari no existeix'),
        );
      });
    }
  });

  group('Seguir', () {
    test('POST i DELETE a /users/{id}/follow', () async {
      final (api, requests) = _api((_) async => http.Response('', 204));

      await api.follow(_laiaId);
      await api.unfollow(_laiaId);

      expect(requests.map((r) => r.method), ['POST', 'DELETE']);
      expect(
        requests.map((r) => r.url.path),
        everyElement('/users/$_laiaId/follow'),
      );
    });

    test('400: no et pots seguir a tu mateix', () async {
      final (api, _) = _api((_) async => http.Response('', 400));
      await expectLater(
        api.follow(_meId),
        _error(status: 400, message: 'No et pots seguir a tu mateix'),
      );
    });

    test('404: usuari no trobat', () async {
      final (api, _) = _api((_) async => http.Response('', 404));
      await expectLater(api.unfollow(_laiaId), _error(status: 404));
    });
  });

  group('Seguidors i seguits', () {
    test('llegeix id i username de cada usuari', () async {
      final (api, requests) = _api(
        (_) async => http.Response(
          _list([
            {'id': 'u1', 'username': 'Núria'},
            {'id': 'u2', 'username': 'jordi'},
          ]),
          200,
        ),
      );

      final followers = await api.fetchFollowers(_laiaId);
      final following = await api.fetchFollowing(_laiaId);

      expect(followers.map((u) => u.username), ['Núria', 'jordi']);
      expect(following.map((u) => u.id), ['u1', 'u2']);
      expect(requests.map((r) => r.url.path), [
        '/users/$_laiaId/followers',
        '/users/$_laiaId/following',
      ]);
    });

    test('el compte propi es tradueix a l\'id real, una sola vegada', () async {
      final (api, requests) = _api((request) async {
        if (request.url.path == '/users/me') {
          return http.Response(
            jsonEncode({
              'id': _meId,
              'email': 'jo@example.cat',
              'username': 'jo',
              'preferences': <String>[],
            }),
            200,
          );
        }
        return http.Response(_list([]), 200);
      });

      await api.fetchFollowers(ownProfileId);
      await api.fetchFollowing(ownProfileId);

      expect(requests.map((r) => r.url.path), [
        '/users/me',
        '/users/$_meId/followers',
        '/users/$_meId/following',
      ]);
    });

    test('si canvia el compte, torna a demanar l\'id propi', () async {
      final session = _MemorySession('token-a');
      final (api, requests) = _api((request) async {
        if (request.url.path == '/users/me') {
          final id = request.headers['authorization'] == 'Bearer token-a'
              ? 'id-a'
              : 'id-b';
          return http.Response(jsonEncode({'id': id}), 200);
        }
        return http.Response(_list([]), 200);
      }, session: session);

      await api.fetchFollowers(ownProfileId);
      session.token = 'token-b';
      await api.fetchFollowers(ownProfileId);

      expect(
        requests.map((r) => r.url.path).where((p) => p.endsWith('followers')),
        ['/users/id-a/followers', '/users/id-b/followers'],
      );
    });

    test('id inexistent o invàlid: 404', () async {
      final (api, _) = _api((_) async => http.Response('', 400));
      await expectLater(api.fetchFollowing('ningu'), _error(status: 404));
    });

    test('resposta amb format inesperat', () async {
      final (api, _) = _api((_) async => http.Response('[]', 200));
      await expectLater(
        api.fetchFollowers(_laiaId),
        _error(message: contains('format esperat')),
      );
    });
  });

  group('Sessió i connexió', () {
    test('sense sessió: 401 sense fer cap petició', () async {
      final (api, requests) = _api(
        (_) async => http.Response('', 200),
        session: _MemorySession(null),
      );
      await expectLater(api.fetchPublicProfile('laia'), _error(status: 401));
      await expectLater(api.follow(_laiaId), _error(status: 401));
      expect(requests, isEmpty);
    });

    test('sessió caducada (401 del servidor)', () async {
      final (api, _) = _api((_) async => http.Response('', 401));
      await expectLater(api.fetchFollowers(_laiaId), _error(status: 401));
    });

    test('sense connexió', () async {
      final (api, _) = _api((_) async => throw const _NetworkError());
      await expectLater(
        api.fetchPublicProfile('laia'),
        _error(message: contains('No s\'ha pogut connectar')),
      );
    });

    test('error del servidor', () async {
      final (api, _) = _api((_) async => http.Response('', 500));
      await expectLater(
        api.fetchPublicProfile('laia'),
        _error(status: 500, message: 'No s\'ha pogut carregar el perfil'),
      );
    });
  });
}

class _NetworkError implements Exception {
  const _NetworkError();
}
