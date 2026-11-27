import 'dart:async';
import 'dart:convert';

import 'package:caliu/data/chat_api.dart';
import 'package:caliu/data/chat_controller.dart';
import 'package:caliu/data/chat_message.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'chat_test_helpers.dart';

ChatController _controller(
  Future<http.Response> Function(http.Request) handler, {
  String? token = 'tok',
  MemorySession? session,
}) => ChatController(
  api: ChatApi(client: MockClient(handler), baseUrl: 'http://api.test'),
  session: session ?? MemorySession(token),
);

http.Response _ok(String reply, {String session = 's1', List? events}) =>
    http.Response(
      jsonEncode({'sessionId': session, 'reply': reply, 'events': ?events}),
      200,
    );

void main() {
  test('sense token demana iniciar sessió', () async {
    final chat = _controller((_) async => _ok('x'), token: null);
    await chat.checkSession();
    expect(chat.checkingSession, isFalse);
    expect(chat.needsLogin, isTrue);
  });

  test('envia, afegeix la resposta i reutilitza la sessió', () async {
    final bodies = <Map<String, dynamic>>[];
    final chat = _controller((request) async {
      bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
      return _ok('Resposta ${bodies.length}', events: [eventJson]);
    });

    await chat.send('  Hola  ');
    await chat.send('I demà?');

    expect(chat.messages.map((m) => m.text), [
      'Hola',
      'Resposta 1',
      'I demà?',
      'Resposta 2',
    ]);
    expect(chat.messages[1].role, ChatRole.assistant);
    expect(chat.messages[1].events.single.id, 'evt-1');
    expect(bodies.first.containsKey('sessionId'), isFalse);
    expect(bodies.last['sessionId'], 's1');
    expect(chat.isTyping, isFalse);
  });

  test('isTyping és cert mentre s\'espera la resposta', () async {
    final pending = Completer<http.Response>();
    final chat = _controller((_) => pending.future);

    final sending = chat.send('Hola');
    await Future<void>.delayed(Duration.zero);
    expect(chat.isTyping, isTrue);
    expect(chat.messages.single.text, 'Hola');

    // Mentre escriu, no es poden enviar més missatges.
    await chat.send('Un altre');
    expect(chat.messages, hasLength(1));

    pending.complete(_ok('Ja està'));
    await sending;
    expect(chat.isTyping, isFalse);
    expect(chat.messages.last.text, 'Ja està');
  });

  test('ignora missatges buits i avisa si són massa llargs', () async {
    var calls = 0;
    final chat = _controller((_) async {
      calls++;
      return _ok('x');
    });

    await chat.send('   ');
    await chat.send('a' * (ChatApi.maxMessageLength + 1));

    expect(calls, 0);
    expect(chat.messages, isEmpty);
    expect(chat.error, contains('massa llarg'));
  });

  test(
    'un error marca el missatge com a no enviat i es pot reintentar',
    () async {
      var fail = true;
      final chat = _controller((_) async {
        if (fail) return http.Response('{}', 503);
        return _ok('Ara sí');
      });

      await chat.send('Hola');
      expect(chat.messages.single.failed, isTrue);
      expect(chat.error, contains('no està disponible'));

      fail = false;
      await chat.retry(chat.messages.single.id);
      expect(chat.messages.first.failed, isFalse);
      expect(chat.messages.last.text, 'Ara sí');
      expect(chat.error, isNull);
    },
  );

  test('401: demana sessió i esborra el token caducat', () async {
    final session = MemorySession('caducat');
    final chat = _controller(
      (_) async => http.Response('{}', 401),
      session: session,
    );

    await chat.send('Hola');

    expect(chat.needsLogin, isTrue);
    expect(session.token, isNull);
    expect(chat.messages.single.failed, isTrue);
  });

  test('404 sense sessió: no és una conversa perduda', () async {
    final chat = _controller(
      (_) async => http.Response('{"error":"Ruta no trobada"}', 404),
    );
    await chat.send('Hola');
    expect(chat.error, contains('ruta no trobada'));
    expect(chat.messages.single.failed, isTrue);
  });

  test('404: oblida la sessió perduda per començar-ne una de nova', () async {
    var call = 0;
    final chat = _controller((_) async {
      call++;
      return call == 2 ? http.Response('{}', 404) : _ok('x');
    });

    await chat.send('Primer');
    expect(chat.sessionId, 's1');
    await chat.send('Segon');
    expect(chat.sessionId, isNull);
  });

  test('reset buida la conversa', () async {
    final chat = _controller((_) async => _ok('x'));
    await chat.send('Hola');
    chat.reset();
    expect(chat.messages, isEmpty);
    expect(chat.sessionId, isNull);
  });
}
