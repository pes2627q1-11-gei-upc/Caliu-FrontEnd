import 'dart:convert';
import 'dart:typed_data';

import 'package:caliu/data/auth_session.dart';
import 'package:caliu/data/avatar_api.dart';
import 'package:caliu/data/avatar_controller.dart';
import 'package:caliu/data/avatar_http_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _baseUrl = 'http://127.0.0.1:3000';
const _avatarUrl = '$_baseUrl/users/u1/avatar/v1';
final _png = Uint8List.fromList([137, 80, 78, 71, 1, 2, 3]);
final _jpeg = Uint8List.fromList([255, 216, 255, 9, 9]);

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

String _me({String? avatarUrl}) => jsonEncode({
  'id': 'u1',
  'email': 'jo@example.cat',
  'username': 'jo',
  'preferences': <String>[],
  'avatarUrl': ?avatarUrl,
});

(HttpAvatarApi, List<http.BaseRequest>) _api(
  Future<http.Response> Function(http.Request request) handler, {
  AuthSessionStore? session,
}) {
  final requests = <http.BaseRequest>[];
  final api = HttpAvatarApi(
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
  isA<AvatarApiException>()
      .having((e) => e.statusCode, 'statusCode', status)
      .having((e) => e.message, 'message', message ?? isA<String>()),
);

void main() {
  group('Llegir la foto', () {
    test('llegeix avatarUrl de /users/me i baixa la imatge', () async {
      final (api, requests) = _api((request) async {
        if (request.url.path == '/users/me') {
          return http.Response(_me(avatarUrl: _avatarUrl), 200);
        }
        return http.Response.bytes(_jpeg, 200);
      });

      expect(await api.fetchAvatar(), _jpeg);
      expect(requests.map((r) => r.url.toString()), [
        '$_baseUrl/users/me',
        _avatarUrl,
      ]);
      expect(requests.first.headers['authorization'], 'Bearer jwt-prova');
    });

    test('sense foto (no hi ha avatarUrl): null sense baixar res', () async {
      final (api, requests) = _api((_) async => http.Response(_me(), 200));
      expect(await api.fetchAvatar(), isNull);
      expect(requests, hasLength(1));
    });

    test('una ruta relativa es completa amb el servidor', () async {
      final (api, requests) = _api((request) async {
        if (request.url.path == '/users/me') {
          return http.Response(_me(avatarUrl: '/users/u1/avatar/v1'), 200);
        }
        return http.Response.bytes(_jpeg, 200);
      });
      await api.fetchAvatar();
      expect(requests.last.url.toString(), _avatarUrl);
    });

    test('foto substituïda (404): es queda sense foto', () async {
      final (api, _) = _api((request) async {
        if (request.url.path == '/users/me') {
          return http.Response(_me(avatarUrl: _avatarUrl), 200);
        }
        return http.Response('', 404);
      });
      expect(await api.fetchAvatar(), isNull);
    });

    test('sense sessió: 401 sense fer cap petició', () async {
      final (api, requests) = _api(
        (_) async => http.Response('', 200),
        session: _MemorySession(null),
      );
      await expectLater(api.fetchAvatar(), _error(status: 401));
      expect(requests, isEmpty);
    });
  });

  group('Pujar la foto', () {
    test('PUT multipart amb el camp avatar i el tipus de la imatge', () async {
      final (api, requests) = _api(
        (_) async => http.Response(jsonEncode({'avatarUrl': _avatarUrl}), 200),
      );

      await api.uploadAvatar(_png, contentType: 'image/png');

      final request = requests.single as http.Request;
      expect(request.method, 'PUT');
      expect(request.url.path, '/users/me/avatar');
      expect(request.headers['authorization'], 'Bearer jwt-prova');
      expect(
        request.headers['content-type'],
        startsWith('multipart/form-data'),
      );
      final body = latin1.decode(request.bodyBytes);
      expect(body, contains('name="avatar"'));
      expect(body, contains('filename="avatar.png"'));
      expect(body, contains('content-type: image/png'));
    });

    test('un JPEG es puja com a image/jpeg', () async {
      final (api, requests) = _api(
        (_) async => http.Response(jsonEncode({'avatarUrl': _avatarUrl}), 200),
      );
      await api.uploadAvatar(_jpeg, contentType: 'image/jpeg');
      final body = latin1.decode((requests.single as http.Request).bodyBytes);
      expect(body, contains('filename="avatar.jpg"'));
      expect(body, contains('content-type: image/jpeg'));
    });

    test('400: imatge no vàlida', () async {
      final (api, _) = _api((_) async => http.Response('', 400));
      await expectLater(
        api.uploadAvatar(_png, contentType: 'image/png'),
        _error(status: 400, message: contains('no és vàlida')),
      );
    });

    test('413: massa gran', () async {
      final (api, _) = _api((_) async => http.Response('', 413));
      await expectLater(
        api.uploadAvatar(_png, contentType: 'image/png'),
        _error(status: 413, message: contains('2 MB')),
      );
    });

    test('sessió caducada (401 del servidor)', () async {
      final (api, _) = _api((_) async => http.Response('', 401));
      await expectLater(
        api.uploadAvatar(_png, contentType: 'image/png'),
        _error(status: 401),
      );
    });

    test('sense connexió', () async {
      final (api, _) = _api((_) async => throw const _NetworkError());
      await expectLater(
        api.uploadAvatar(_png, contentType: 'image/png'),
        _error(message: contains('No s\'ha pogut connectar')),
      );
    });
  });

  test('el controlador: pujar i tornar a llegir la foto', () async {
    Uint8List? stored;
    final (api, _) = _api((request) async {
      if (request.method == 'PUT') {
        stored = _jpeg; // el backend la normalitza a JPEG
        return http.Response(jsonEncode({'avatarUrl': _avatarUrl}), 200);
      }
      if (request.url.path == '/users/me') {
        return http.Response(
          _me(avatarUrl: stored == null ? null : _avatarUrl),
          200,
        );
      }
      return http.Response.bytes(stored!, 200);
    });
    final avatar = AvatarController(api);

    await avatar.load();
    expect(avatar.bytes, isNull);

    await avatar.upload(_png, contentType: 'image/png');
    expect(avatar.bytes, _png);

    await avatar.load();
    expect(avatar.bytes, _jpeg);
  });
}

class _NetworkError implements Exception {
  const _NetworkError();
}
