import 'dart:convert';

import 'package:caliu/data/auth_api.dart';
import 'package:caliu/data/event.dart';
import 'package:caliu/data/event_query.dart';
import 'package:caliu/data/events_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _user = {
  'id': '507f1f77bcf86cd799439011',
  'username': 'marc',
  'email': 'marc@example.com',
  'preferences': <String>['Música'],
};

String _authBody() => jsonEncode({
  'user': _user,
  'token': 'jwt-token',
  'tokenType': 'Bearer',
  'expiresIn': 3600,
});

String _userBody({String username = 'marc'}) => jsonEncode({
  ..._user,
  'username': username,
});

void main() {
  group('AuthApi registre i login', () {
    test('el registre fa register → login → PATCH username', () async {
      final paths = <String>[];
      final client = MockClient((request) async {
        paths.add('${request.method} ${request.url.path}');
        expect(request.headers['content-type'], 'application/json');
        switch (request.url.path) {
          case '/auth/register':
            expect(jsonDecode(request.body), {
              'email': 'marc@example.com',
              'password': 'contrasenya-segura',
            });
            return http.Response(
              jsonEncode({'user': {..._user, 'username': null}}),
              201,
            );
          case '/auth/login':
            expect(jsonDecode(request.body), {
              'email': 'marc@example.com',
              'password': 'contrasenya-segura',
            });
            return http.Response(
              jsonEncode({
                'user': {..._user, 'username': null},
                'token': 'jwt-token',
                'tokenType': 'Bearer',
                'expiresIn': 3600,
              }),
              200,
            );
          case '/users/me':
            expect(request.method, 'PATCH');
            expect(request.headers['authorization'], 'Bearer jwt-token');
            expect(jsonDecode(request.body), {'username': 'marc'});
            return http.Response(_userBody(), 200);
          default:
            fail('ruta inesperada: ${request.url.path}');
        }
      });
      final api = AuthApi(client: client, baseUrl: 'http://localhost:3000');

      final result = await api.register(
        username: ' marc ',
        email: 'marc@example.com',
        password: 'contrasenya-segura',
      );

      expect(paths, [
        'POST /auth/register',
        'POST /auth/login',
        'PATCH /users/me',
      ]);
      expect(result.token, 'jwt-token');
      expect(result.user.id, _user['id']);
      expect(result.user.username, 'marc');
      expect(result.user.preferences, ['Música']);
    });

    test('el login processa el mateix esquema d’autenticació', () async {
      final client = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/auth/login');
        expect(jsonDecode(request.body), {
          'email': 'marc@example.com',
          'password': 'contrasenya-segura',
        });
        return http.Response(_authBody(), 200);
      });
      final api = AuthApi(client: client, baseUrl: 'http://localhost:3000');

      final result = await api.login(
        email: ' marc@example.com ',
        password: 'contrasenya-segura',
      );

      expect(result.token, 'jwt-token');
      expect(result.user.username, 'marc');
    });

    test('rebutja respostes d’autenticació incompletes o malformades', () async {
      for (final body in [
        '{"token":"jwt-token","profile":{}}',
        '{"user":{},"token":"jwt-token","tokenType":"Bearer","expiresIn":3600}',
        'no és json',
      ]) {
        final api = AuthApi(
          client: MockClient((_) async => http.Response(body, 200)),
          baseUrl: 'http://localhost:3000',
        );
        await expectLater(
          api.login(email: 'marc@example.com', password: 'contrasenya-segura'),
          throwsA(isA<AuthApiException>()),
        );
      }
    });

    test('gestiona explícitament els errors HTTP del backend', () async {
      for (final status in [400, 401, 409, 429, 500]) {
        final api = AuthApi(
          client: MockClient(
            (_) async => http.Response('{"error":"detall públic"}', status),
          ),
          baseUrl: 'http://localhost:3000',
        );
        await expectLater(
          api.login(email: 'marc@example.com', password: 'contrasenya-segura'),
          throwsA(
            isA<AuthApiException>().having(
              (error) => error.statusCode,
              'statusCode',
              status,
            ),
          ),
        );
      }
    });

    test('no exposa detalls de connexió si la xarxa falla', () async {
      final api = AuthApi(
        client: MockClient((_) async => throw Exception('secret socket data')),
        baseUrl: 'http://localhost:3000',
      );
      await expectLater(
        api.login(email: 'marc@example.com', password: 'contrasenya-segura'),
        throwsA(
          isA<AuthApiException>().having(
            (error) => error.message,
            'message',
            isNot(contains('secret socket data')),
          ),
        ),
      );
    });
  });

  group('AuthApi perfil i preferències', () {
    test('GET /users/me envia Bearer i parseja el perfil', () async {
      final client = MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/users/me');
        expect(request.headers['authorization'], 'Bearer jwt-token');
        return http.Response(_userBody(), 200);
      });
      final profile = await AuthApi(
        client: client,
        baseUrl: 'http://localhost:3000',
      ).fetchProfile('jwt-token');
      expect(profile.email, 'marc@example.com');
    });

    test('PATCH /users/me actualitza username amb Bearer', () async {
      final client = MockClient((request) async {
        expect(request.method, 'PATCH');
        expect(request.url.path, '/users/me');
        expect(request.headers['authorization'], 'Bearer jwt-token');
        expect(jsonDecode(request.body), {'username': 'marc_nou'});
        return http.Response(_userBody(username: 'marc_nou'), 200);
      });
      final profile = await AuthApi(
        client: client,
        baseUrl: 'http://localhost:3000',
      ).updateProfile(token: 'jwt-token', username: ' marc_nou ');
      expect(profile.username, 'marc_nou');
    });

    test('consulta preferències actuals', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/users/me/preferences');
        expect(request.headers['authorization'], 'Bearer jwt-token');
        return http.Response('{"preferences":["Música","Teatre"]}', 200);
      });
      final preferences = await AuthApi(
        client: client,
        baseUrl: 'http://localhost:3000',
      ).fetchPreferences('jwt-token');
      expect(preferences, ['Música', 'Teatre']);
    });

    test('substitueix preferències i permet una llista buida', () async {
      final client = MockClient((request) async {
        expect(request.method, 'PUT');
        expect(request.url.path, '/users/me/preferences');
        expect(request.headers['authorization'], 'Bearer jwt-token');
        expect(jsonDecode(request.body), {'preferences': <String>[]});
        return http.Response('{"preferences":[]}', 200);
      });
      final preferences = await AuthApi(
        client: client,
        baseUrl: 'http://localhost:3000',
      ).updatePreferences(token: 'jwt-token', preferences: []);
      expect(preferences, isEmpty);
    });

    test('categories provenen de GET /events/categories', () async {
      final client = MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/events/categories');
        return http.Response('{"categories":["Música","Teatre"]}', 200);
      });
      final categories = await AuthApi(
        client: client,
        baseUrl: 'http://localhost:3000',
      ).fetchCategories();
      expect(categories, ['Música', 'Teatre']);
    });
  });

  group('AuthApi.logout', () {
    test('accepta 204 amb cos buit i només envia el token actual', () async {
      final client = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/auth/logout');
        expect(request.headers['authorization'], 'Bearer jwt-token');
        return http.Response('', 204);
      });
      await expectLater(
        AuthApi(client: client, baseUrl: 'http://localhost:3000').logout(
          'jwt-token',
        ),
        completes,
      );
    });

    test('considera revocada una sessió que ja retorna 401', () async {
      final api = AuthApi(
        client: MockClient((_) async => http.Response('', 401)),
        baseUrl: 'http://localhost:3000',
      );
      await expectLater(api.logout('expired-token'), completes);
    });

    test('informa errors de xarxa sense revelar-ne els detalls', () async {
      final api = AuthApi(
        client: MockClient((_) async => throw Exception('internal detail')),
        baseUrl: 'http://localhost:3000',
      );
      await expectLater(
        api.logout('jwt-token'),
        throwsA(
          isA<AuthApiException>().having(
            (error) => error.message,
            'message',
            isNot(contains('internal detail')),
          ),
        ),
      );
    });
  });

  group('Event.fromJson', () {
    test('parseja GeoJSON [lng, lat] i camps bàsics', () {
      final event = Event.fromJson({
        'id': 'abc',
        'title': 'Concert',
        'venue': 'Sala',
        'municipality': 'Barcelona',
        'categories': ['Música'],
        'url': 'https://example.com',
        'images': ['https://example.com/a.jpg'],
        'location': {
          'type': 'Point',
          'coordinates': [2.17, 41.38],
        },
        'distanceMeters': 1200,
      });

      expect(event.id, 'abc');
      expect(event.title, 'Concert');
      expect(event.categories, ['Música']);
      expect(event.url, 'https://example.com');
      expect(event.imageUrl, 'https://example.com/a.jpg');
      expect(event.location?.latitude, closeTo(41.38, 0.001));
      expect(event.location?.longitude, closeTo(2.17, 0.001));
      expect(event.distanceMeters, 1200);
      expect(event.placeLine, contains('Sala'));
    });

    test('tolera JSON mínim sense location', () {
      final event = Event.fromJson({'id': '1'});
      expect(event.title, 'Sense títol');
      expect(event.hasLocation, isFalse);
      expect(event.images, isEmpty);
    });
  });

  group('EventQuery', () {
    test('toQueryParameters omet radi si no hi ha lat/lng', () {
      final q = EventQuery(q: 'farinera', radiusKm: 50, page: 2);
      final params = q.toQueryParameters();
      expect(params['q'], 'farinera');
      expect(params['page'], '2');
      expect(params.containsKey('radiusKm'), isFalse);
      expect(params.containsKey('lat'), isFalse);
    });

    test('inclou lat/lng i radi quan hi són', () {
      final q = EventQuery(lat: 41.4, lng: 2.1, radiusKm: 15);
      final params = q.toQueryParameters();
      expect(params['lat'], '41.4');
      expect(params['lng'], '2.1');
      expect(params['radiusKm'], anyOf('15', '15.0'));
    });
  });

  group('EventsApi.fetchHealth', () {
    test('ok quan /health respon 200', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/health');
        return http.Response(
          '{"status":"ok","service":"api-node"}',
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final api = EventsApi(client: client, baseUrl: 'http://127.0.0.1:3000');
      final health = await api.fetchHealth();
      expect(health.ok, isTrue);
      expect(health.service, 'api-node');
      expect(health.baseUrl, 'http://127.0.0.1:3000');
    });

    test('no ok si la xarxa falla', () async {
      final client = MockClient((request) async {
        throw Exception('connection refused');
      });
      final api = EventsApi(client: client, baseUrl: 'http://127.0.0.1:3000');
      final health = await api.fetchHealth();
      expect(health.ok, isFalse);
      expect(health.error, isNotNull);
    });
  });
}
