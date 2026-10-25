import 'package:caliu/data/auth_api.dart';
import 'package:caliu/data/event.dart';
import 'package:caliu/data/event_query.dart';
import 'package:caliu/data/events_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('AuthApi.register', () {
    test(
      'envia les credencials i interpreta la resposta del backend',
      () async {
        final client = MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/auth/register');
          expect(request.headers['content-type'], 'application/json');
          expect(
            request.body,
            '{"username":"marc","email":"marc@example.com","password":"contrasenya-segura"}',
          );
          return http.Response(
            '{"token":"jwt-token","profile":{"username":"marc","email":"marc@example.com"}}',
            201,
            headers: {'content-type': 'application/json'},
          );
        });
        final api = AuthApi(client: client, baseUrl: 'http://localhost:3000');

        final result = await api.register(
          username: ' marc ',
          email: 'marc@example.com',
          password: 'contrasenya-segura',
        );

        expect(result.token, 'jwt-token');
        expect(result.username, 'marc');
        expect(result.email, 'marc@example.com');
      },
    );

    test('explica quan el nom o el correu ja estan en ús', () async {
      final client = MockClient((request) async {
        return http.Response('{"error":"Username o email ja està en ús"}', 409);
      });
      final api = AuthApi(client: client, baseUrl: 'http://localhost:3000');

      await expectLater(
        api.register(
          username: 'marc',
          email: 'marc@example.com',
          password: 'contrasenya-segura',
        ),
        throwsA(
          isA<AuthApiException>().having(
            (error) => error.message,
            'message',
            'Aquest correu electrònic o nom d’usuari ja està en ús.',
          ),
        ),
      );
    });

    group('AuthApi.login', () {
      test('envia email i contrasenya i retorna el token de sessió', () async {
        final client = MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/auth/login');
          expect(
            request.body,
            '{"email":"marc@example.com","password":"contrasenya-segura"}',
          );
          return http.Response(
            '{"token":"jwt-token","profile":{"username":"marc","email":"marc@example.com"}}',
            200,
          );
        });
        final api = AuthApi(client: client, baseUrl: 'http://localhost:3000');

        final result = await api.login(
          email: ' marc@example.com ',
          password: 'contrasenya-segura',
        );

        expect(result.token, 'jwt-token');
        expect(result.username, 'marc');
      });

      test(
        'retorna un error clar quan les credencials són incorrectes',
        () async {
          final client = MockClient((request) async {
            return http.Response('{"error":"Credencials incorrectes"}', 401);
          });
          final api = AuthApi(client: client, baseUrl: 'http://localhost:3000');

          await expectLater(
            api.login(
              email: 'marc@example.com',
              password: 'contrasenya-segura',
            ),
            throwsA(
              isA<AuthApiException>()
                  .having((error) => error.statusCode, 'statusCode', 401)
                  .having(
                    (error) => error.message,
                    'message',
                    'Credencials incorrectes',
                  ),
            ),
          );
        },
      );
    });

    group('AuthApi.fetchProfile', () {
      test(
        'envia el token i retorna les dades del perfil autenticat',
        () async {
          final client = MockClient((request) async {
            expect(request.method, 'GET');
            expect(request.url.path, '/profile');
            expect(request.headers['authorization'], 'Bearer jwt-token');
            return http.Response(
              '{"id":"user-id","username":"marc","email":"marc@example.com","preferences":["Música"]}',
              200,
            );
          });
          final api = AuthApi(client: client, baseUrl: 'http://localhost:3000');

          final profile = await api.fetchProfile('jwt-token');

          expect(profile.id, 'user-id');
          expect(profile.username, 'marc');
          expect(profile.preferences, ['Música']);
        },
      );

      test('rebutja el perfil si el token no és vàlid', () async {
        final client = MockClient((request) async {
          return http.Response('{"error":"Token absent o invàlid"}', 401);
        });
        final api = AuthApi(client: client, baseUrl: 'http://localhost:3000');

        await expectLater(
          api.fetchProfile('invalid-token'),
          throwsA(
            isA<AuthApiException>().having(
              (error) => error.statusCode,
              'statusCode',
              401,
            ),
          ),
        );
      });
    });

    group('AuthApi.updateProfile', () {
      test('actualitza el username amb Bearer token', () async {
        final client = MockClient((request) async {
          expect(request.method, 'PATCH');
          expect(request.url.path, '/profile');
          expect(request.headers['authorization'], 'Bearer jwt-token');
          expect(request.body, '{"username":"marc nou"}');
          return http.Response(
            '{"id":"user-id","username":"marc nou","email":"marc@example.com","preferences":[]}',
            200,
          );
        });
        final api = AuthApi(client: client, baseUrl: 'http://localhost:3000');

        final profile = await api.updateProfile(
          token: 'jwt-token',
          username: ' marc nou ',
        );

        expect(profile.username, 'marc nou');
        expect(profile.email, 'marc@example.com');
      });

      test('informa si el username ja està en ús', () async {
        final client = MockClient((request) async {
          return http.Response('{"error":"Username ja està en ús"}', 409);
        });
        final api = AuthApi(client: client, baseUrl: 'http://localhost:3000');

        await expectLater(
          api.updateProfile(token: 'jwt-token', username: 'existent'),
          throwsA(
            isA<AuthApiException>()
                .having((error) => error.statusCode, 'statusCode', 409)
                .having(
                  (error) => error.message,
                  'message',
                  'Aquest nom d’usuari ja està en ús.',
                ),
          ),
        );
      });
    });

    test('mostra el detall de validació retornat pel backend', () async {
      final client = MockClient((request) async {
        return http.Response('{"error":"email no és vàlid"}', 400);
      });
      final api = AuthApi(client: client, baseUrl: 'http://localhost:3000');

      await expectLater(
        api.register(
          username: 'marc',
          email: 'incorrecte',
          password: 'contrasenya-segura',
        ),
        throwsA(
          isA<AuthApiException>().having(
            (error) => error.message,
            'message',
            'email no és vàlid',
          ),
        ),
      );
    });
  });

  group('AuthApi.logout', () {
    test('revoca la sessió actual amb el token Bearer', () async {
      final client = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/auth/logout');
        expect(request.headers['authorization'], 'Bearer jwt-token');
        return http.Response('', 204);
      });
      final api = AuthApi(client: client, baseUrl: 'http://localhost:3000');

      await expectLater(api.logout('jwt-token'), completes);
    });

    test('considera tancada una sessió ja no vàlida', () async {
      final client = MockClient((request) async {
        return http.Response('{"error":"Sessió no vàlida"}', 401);
      });
      final api = AuthApi(client: client, baseUrl: 'http://localhost:3000');

      await expectLater(api.logout('expired-token'), completes);
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
