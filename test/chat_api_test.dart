import 'dart:convert';

import 'package:caliu/data/chat_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'chat_test_helpers.dart';

ChatApi _api(Future<http.Response> Function(http.Request) handler) =>
    ChatApi(client: MockClient(handler), baseUrl: 'http://api.test');

void main() {
  group('ChatApi.sendMessage', () {
    test('POST amb JWT i JSON; sense sessionId la primera vegada', () async {
      late http.Request seen;
      final api = _api((request) async {
        seen = request;
        return http.Response(
          jsonEncode({'sessionId': 's1', 'reply': ' Hola! '}),
          200,
        );
      });

      final reply = await api.sendMessage(token: 'tok', message: 'Hola');

      expect(seen.method, 'POST');
      expect(seen.url.toString(), 'http://api.test/chat/messages');
      expect(seen.headers['Authorization'], 'Bearer tok');
      expect(jsonDecode(seen.body), {'message': 'Hola'});
      expect(reply.sessionId, 's1');
      expect(reply.reply, 'Hola!');
      expect(reply.events, isEmpty);
    });

    test('envia el sessionId quan continua una conversa', () async {
      late http.Request seen;
      final api = _api((request) async {
        seen = request;
        return http.Response('{"sessionId":"s1","reply":"Ok"}', 200);
      });

      await api.sendMessage(token: 'tok', message: 'I demà?', sessionId: 's1');

      expect(jsonDecode(seen.body), {'message': 'I demà?', 'sessionId': 's1'});
    });

    test('llegeix els esdeveniments opcionals i salta els mal formats', () async {
      final api = _api(
        (_) async => http.Response(
          jsonEncode({
            'sessionId': 's1',
            'reply': 'Et proposo això',
            'events': [eventJson, 'no-es-un-objecte', {'title': 'sense id'}],
          }),
          200,
        ),
      );

      final reply = await api.sendMessage(token: 'tok', message: 'Plans');

      expect(reply.events, hasLength(1));
      expect(reply.events.single.id, 'evt-1');
      expect(reply.events.single.title, 'Concert al Parc');
    });

    test('resposta 200 sense reply és un error', () async {
      final api = _api((_) async => http.Response('{"sessionId":"s1"}', 200));
      await expectLater(
        api.sendMessage(token: 'tok', message: 'x'),
        throwsA(isA<ChatApiException>()),
      );
    });

    test('tradueix els codis d\'error', () async {
      Future<ChatApiException> errorFor(int status, [String body = '{}']) async {
        final api = _api((_) async => http.Response(body, status));
        try {
          await api.sendMessage(token: 'tok', message: 'x');
        } on ChatApiException catch (e) {
          return e;
        }
        fail('Havia de llançar ChatApiException');
      }

      final unauthorized = await errorFor(401);
      expect(unauthorized.isUnauthorized, isTrue);
      expect(unauthorized.message, contains('sessió'));

      final lost = await errorFor(404);
      expect(lost.isSessionLost, isTrue);

      final limited = await errorFor(429, '{"error":"Límit assolit"}');
      expect(limited.message, 'Límit assolit');

      final down = await errorFor(503);
      expect(down.message, contains('no està disponible'));

      final invalid = await errorFor(400, '{"error":"Camp \\"message\\" obligatori"}');
      expect(invalid.message, 'Camp "message" obligatori');
    });

    test('error de xarxa', () async {
      final api = _api((_) async => throw http.ClientException('offline'));
      await expectLater(
        api.sendMessage(token: 'tok', message: 'x'),
        throwsA(
          isA<ChatApiException>().having(
            (e) => e.message,
            'message',
            contains('connectar'),
          ),
        ),
      );
    });
  });
}
