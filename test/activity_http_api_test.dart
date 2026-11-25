import 'dart:convert';

import 'package:caliu/data/activity_api.dart';
import 'package:caliu/data/activity_http_api.dart';
import 'package:caliu/data/attended_api.dart';
import 'package:caliu/data/auth_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _baseUrl = 'http://127.0.0.1:3000';

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

Map<String, dynamic> _event(String id, String title, String start) => {
  'id': id,
  'title': title,
  'startDate': start,
  'municipality': 'Barcelona',
};

(AttendanceHttpClient, List<http.Request>) _client(
  Future<http.Response> Function(http.Request request) handler, {
  AuthSessionStore? session,
}) {
  final requests = <http.Request>[];
  final client = AttendanceHttpClient(
    client: MockClient((request) {
      requests.add(request);
      return handler(request);
    }),
    baseUrl: _baseUrl,
    session: session ?? _MemorySession(),
  );
  return (client, requests);
}

void main() {
  group('HttpActivityApi', () {
    test('llegeix les assistències amb el token', () async {
      final (client, requests) = _client(
        (_) async => http.Response(
          jsonEncode({
            'items': [
              {
                'id': 'a1',
                'event': _event('e1', 'Concert', '2026-11-20T18:00:00Z'),
                'attendedAt': '2026-11-20T19:00:00Z',
              },
              {
                'id': 'a2',
                'event': _event('e2', 'Fira', '2026-08-01T10:00:00Z'),
                'attendedAt': '2026-08-01T11:00:00Z',
              },
            ],
          }),
          200,
        ),
      );

      final entries = await HttpActivityApi(client).fetchActivity();

      expect(entries.map((e) => e.id), ['a1', 'a2']);
      expect(entries.first.event.title, 'Concert');
      expect(entries.first.at.toUtc(), DateTime.utc(2026, 11, 20, 19));
      expect(requests.single.url.toString(), '$_baseUrl/users/me/activity');
      expect(requests.single.headers['authorization'], 'Bearer jwt-prova');
    });

    test('descarta les entrades incompletes', () async {
      final (client, _) = _client(
        (_) async => http.Response(
          jsonEncode({
            'items': [
              {'id': 'a1', 'event': _event('e1', 'Concert', '2026-11-20')},
              {'id': 'a2', 'attendedAt': '2026-11-20T19:00:00Z'},
              {
                'id': 'a3',
                'event': _event('e3', 'Fira', '2026-11-20'),
                'attendedAt': '2026-11-20T19:00:00Z',
              },
            ],
          }),
          200,
        ),
      );
      final entries = await HttpActivityApi(client).fetchActivity();
      expect(entries.map((e) => e.id), ['a3']);
    });

    test('sense sessió: 401 sense fer cap petició', () async {
      final (client, requests) = _client(
        (_) async => http.Response('', 200),
        session: _MemorySession(null),
      );
      await expectLater(
        HttpActivityApi(client).fetchActivity(),
        throwsA(
          isA<ActivityApiException>().having(
            (e) => e.isUnauthorized,
            'isUnauthorized',
            isTrue,
          ),
        ),
      );
      expect(requests, isEmpty);
    });

    test('error del servidor', () async {
      final (client, _) = _client((_) async => http.Response('', 500));
      await expectLater(
        HttpActivityApi(client).fetchActivity(),
        throwsA(
          isA<ActivityApiException>()
              .having((e) => e.statusCode, 'statusCode', 500)
              .having(
                (e) => e.message,
                'message',
                'No s\'ha pogut carregar l\'activitat',
              ),
        ),
      );
    });
  });

  group('HttpAttendedApi', () {
    test('llegeix els esdeveniments acabats', () async {
      final (client, requests) = _client(
        (_) async => http.Response(
          jsonEncode({
            'items': [
              _event('e1', 'Concert', '2026-11-20T18:00:00Z'),
              _event('e2', 'Fira', '2025-07-10T10:00:00Z'),
            ],
          }),
          200,
        ),
      );

      final events = await HttpAttendedApi(client).fetchAttended();

      expect(events.map((e) => e.title), ['Concert', 'Fira']);
      expect(events.last.startDate?.year, 2025);
      expect(requests.single.url.path, '/users/me/attended');
    });

    test('llista buida', () async {
      final (client, _) = _client(
        (_) async => http.Response('{"items":[]}', 200),
      );
      expect(await HttpAttendedApi(client).fetchAttended(), isEmpty);
    });

    test('sessió caducada (401 del servidor)', () async {
      final (client, _) = _client((_) async => http.Response('', 401));
      await expectLater(
        HttpAttendedApi(client).fetchAttended(),
        throwsA(
          isA<AttendedApiException>().having(
            (e) => e.isUnauthorized,
            'isUnauthorized',
            isTrue,
          ),
        ),
      );
    });

    test('sense connexió', () async {
      final (client, _) = _client((_) async => throw const _NetworkError());
      await expectLater(
        HttpAttendedApi(client).fetchAttended(),
        throwsA(
          isA<AttendedApiException>().having(
            (e) => e.message,
            'message',
            contains('No s\'ha pogut connectar'),
          ),
        ),
      );
    });

    test('resposta amb format inesperat', () async {
      final (client, _) = _client((_) async => http.Response('[]', 200));
      await expectLater(
        HttpAttendedApi(client).fetchAttended(),
        throwsA(
          isA<AttendedApiException>().having(
            (e) => e.message,
            'message',
            contains('format esperat'),
          ),
        ),
      );
    });
  });
}

class _NetworkError implements Exception {
  const _NetworkError();
}
