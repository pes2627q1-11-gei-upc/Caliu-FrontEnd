import 'dart:convert';

import 'package:caliu/data/auth_session.dart';
import 'package:caliu/data/event.dart';
import 'package:caliu/data/favorites_api.dart';
import 'package:caliu/data/favorites_controller.dart';
import 'package:caliu/data/favorites_http_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _baseUrl = 'http://127.0.0.1:3000';
const _id1 = '6710f1c2a1b2c3d4e5f60718';
const _id2 = '6710f1c2a1b2c3d4e5f60719';

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

Map<String, dynamic> _favoriteJson(String id, String title, {bool? alerts}) => {
  'id': id,
  'title': title,
  'isFavorite': true,
  'location': {
    'type': 'Point',
    'coordinates': [2.17, 41.38],
  },
  'notificacionsActives': ?alerts,
};

String _listBody(List<Map<String, dynamic>> items) =>
    jsonEncode({'items': items});

/// Client que respon segons [handler] i guarda les peticions rebudes.
(FavoritesHttpClient, List<http.Request>) _client(
  Future<http.Response> Function(http.Request request) handler, {
  AuthSessionStore? session,
}) {
  final requests = <http.Request>[];
  final client = FavoritesHttpClient(
    client: MockClient((request) {
      requests.add(request);
      return handler(request);
    }),
    baseUrl: _baseUrl,
    session: session ?? _MemorySession(),
  );
  return (client, requests);
}

Matcher _error({int? status, Object? message}) => throwsA(
  isA<FavoritesApiException>()
      .having((e) => e.statusCode, 'statusCode', status)
      .having((e) => e.message, 'message', message ?? isA<String>()),
);

void main() {
  group('HttpFavoritesApi', () {
    test('GET llegeix els preferits amb el token', () async {
      final (client, requests) = _client(
        (_) async => http.Response(
          _listBody([
            _favoriteJson(_id1, 'Concert al Parc', alerts: true),
            _favoriteJson(_id2, 'Fira del Llibre', alerts: false),
          ]),
          200,
        ),
      );

      final favorites = await HttpFavoritesApi(client).fetchFavorites();

      expect(favorites.map((e) => e.id), [_id1, _id2]);
      expect(favorites.first.title, 'Concert al Parc');
      expect(favorites.first.hasLocation, isTrue);
      final request = requests.single;
      expect(request.method, 'GET');
      expect(request.url.toString(), '$_baseUrl/users/me/favorites');
      expect(request.headers['authorization'], 'Bearer jwt-prova');
    });

    test('llista buida', () async {
      final (client, _) = _client(
        (_) async => http.Response(_listBody([]), 200),
      );
      expect(await HttpFavoritesApi(client).fetchFavorites(), isEmpty);
    });

    test('POST envia l\'eventId i accepta el 204', () async {
      final (client, requests) = _client((_) async => http.Response('', 204));

      await HttpFavoritesApi(client)
          .addFavorite(const Event(id: _id1, title: 'Concert'));

      final request = requests.single;
      expect(request.method, 'POST');
      expect(request.url.path, '/users/me/favorites');
      expect(request.headers['content-type'], startsWith('application/json'));
      expect(jsonDecode(request.body), {'eventId': _id1});
    });

    test(
      'POST d\'un esdeveniment que ja no existeix: 404 amb missatge',
      () async {
        final (client, _) = _client(
          (_) async => http.Response('{"error":"Not found"}', 404),
        );
        await expectLater(
          HttpFavoritesApi(client)
              .addFavorite(const Event(id: _id1, title: 'Concert')),
          _error(status: 404, message: 'Aquest esdeveniment ja no existeix'),
        );
      },
    );

    test('DELETE fa servir l\'eventId a la ruta', () async {
      final (client, requests) = _client((_) async => http.Response('', 204));

      await HttpFavoritesApi(client).removeFavorite(_id1);

      final request = requests.single;
      expect(request.method, 'DELETE');
      expect(request.url.path, '/users/me/favorites/$_id1');
      expect(request.headers['authorization'], 'Bearer jwt-prova');
    });

    test('isFavorite consulta la llista', () async {
      final (client, _) = _client(
        (_) async =>
            http.Response(_listBody([_favoriteJson(_id1, 'Concert')]), 200),
      );
      final api = HttpFavoritesApi(client);
      expect(await api.isFavorite(_id1), isTrue);
      expect(await api.isFavorite(_id2), isFalse);
    });
  });

  group('HttpFavoriteAlertsApi', () {
    test(
      'silenciats són els preferits amb notificacionsActives a false',
      () async {
        final (client, _) = _client(
          (_) async => http.Response(
            _listBody([
              _favoriteJson(_id1, 'Concert', alerts: true),
              _favoriteJson(_id2, 'Fira', alerts: false),
            ]),
            200,
          ),
        );
        expect(await HttpFavoriteAlertsApi(client).fetchMuted(), {_id2});
      },
    );

    test(
      'si el backend no envia el camp, les alertes es consideren actives',
      () async {
        final (client, _) = _client(
          (_) async =>
              http.Response(_listBody([_favoriteJson(_id1, 'Concert')]), 200),
        );
        expect(await HttpFavoriteAlertsApi(client).fetchMuted(), isEmpty);
      },
    );

    test('PATCH envia notificacionsActives', () async {
      final (client, requests) = _client((_) async => http.Response('', 204));

      await HttpFavoriteAlertsApi(client)
          .setAlertsEnabled(_id1, enabled: false);

      final request = requests.single;
      expect(request.method, 'PATCH');
      expect(request.url.path, '/users/me/favorites/$_id1');
      expect(jsonDecode(request.body), {'notificacionsActives': false});
    });

    test('PATCH d\'un preferit que ja no hi és: 404 amb missatge', () async {
      final (client, _) = _client((_) async => http.Response('', 404));
      await expectLater(
        HttpFavoriteAlertsApi(client).setAlertsEnabled(_id1, enabled: true),
        _error(
          status: 404,
          message: 'Aquest esdeveniment ja no és als teus preferits',
        ),
      );
    });
  });

  group('Errors', () {
    test('sense sessió: 401 sense fer cap petició', () async {
      final (client, requests) = _client(
        (_) async => http.Response('', 200),
        session: _MemorySession(null),
      );
      await expectLater(
        HttpFavoritesApi(client).fetchFavorites(),
        throwsA(
          isA<FavoritesApiException>().having(
            (e) => e.isUnauthorized,
            'isUnauthorized',
            isTrue,
          ),
        ),
      );
      expect(requests, isEmpty);
    });

    test('el servidor respon 401 (sessió caducada)', () async {
      final (client, _) = _client((_) async => http.Response('', 401));
      await expectLater(
        HttpFavoritesApi(client).removeFavorite(_id1),
        _error(status: 401),
      );
    });

    test('error del servidor: missatge general amb el codi', () async {
      final (client, _) = _client((_) async => http.Response('', 500));
      await expectLater(
        HttpFavoritesApi(client).fetchFavorites(),
        _error(status: 500, message: 'No s\'han pogut carregar els preferits'),
      );
    });

    test('sense connexió: missatge clar', () async {
      final (client, _) = _client(
        (_) async => throw const SocketExceptionLike(),
      );
      await expectLater(
        HttpFavoritesApi(client).fetchFavorites(),
        _error(message: contains('No s\'ha pogut connectar')),
      );
    });

    test('resposta amb format inesperat', () async {
      final (client, _) = _client(
        (_) async => http.Response('{"preferits":[]}', 200),
      );
      await expectLater(
        HttpFavoritesApi(client).fetchFavorites(),
        _error(message: 'La llista de preferits no té el format esperat'),
      );
    });
  });

  test('el controlador funciona igual amb el backend real', () async {
    var stored = <Map<String, dynamic>>[];
    final (client, _) = _client((request) async {
      switch (request.method) {
        case 'GET':
          return http.Response(_listBody(stored), 200);
        case 'POST':
          final id = (jsonDecode(request.body) as Map)['eventId'] as String;
          stored = [_favoriteJson(id, 'Concert'), ...stored];
          return http.Response('', 204);
        case 'DELETE':
          final id = request.url.pathSegments.last;
          stored = stored.where((e) => e['id'] != id).toList();
          return http.Response('', 204);
      }
      return http.Response('', 500);
    });
    final favorites = FavoritesController(HttpFavoritesApi(client));

    await favorites.load();
    expect(favorites.favorites, isEmpty);

    await favorites.toggle(const Event(id: _id1, title: 'Concert'));
    expect(favorites.isFavorite(_id1), isTrue);
    await favorites.load();
    expect(favorites.isFavorite(_id1), isTrue);

    await favorites.toggle(const Event(id: _id1, title: 'Concert'));
    await favorites.load();
    expect(favorites.isFavorite(_id1), isFalse);
  });
}

/// Error de xarxa simulat (com un `SocketException`).
class SocketExceptionLike implements Exception {
  const SocketExceptionLike();
}
