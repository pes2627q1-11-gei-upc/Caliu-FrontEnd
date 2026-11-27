import 'dart:convert';

import 'package:caliu/chat_screen.dart';
import 'package:caliu/data/chat_api.dart';
import 'package:caliu/data/chat_controller.dart';
import 'package:caliu/data/chat_demo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'chat_test_helpers.dart';

ChatApi _api(Future<http.Response> Function(http.Request) handler) =>
    ChatApi(client: MockClient(handler), baseUrl: 'http://api.test');

http.Response _json(Map<String, Object?> body, [int status = 200]) =>
    http.Response(jsonEncode(body), status);

http.Response _fallback({String? session}) => _json({
  'sessionId': session,
  'type': 'fallback',
  'reply': 'Ara mateix no puc respondre del tot.',
  'events': [],
  'filters': null,
});

http.Response _text(String reply) => _json({
  'sessionId': 's1',
  'type': 'text',
  'reply': reply,
  'events': [],
  'filters': null,
});

ChatController _controller(
  Future<http.Response> Function(http.Request) handler,
) => ChatController(
  api: _api(withoutHistory(handler)),
  session: MemorySession('tok'),
  locale: () => 'ca',
);

void main() {
  group('ChatApi: resposta alternativa i codis d\'error (#144)', () {
    test('una resposta alternativa pot venir sense sessió', () async {
      final reply = await _api((_) async => _fallback())
          .sendMessage(token: 'tok', message: 'Hola');

      expect(reply.isFallback, isTrue);
      expect(reply.sessionId, isNull);
      expect(reply.reply, 'Ara mateix no puc respondre del tot.');
    });

    test('una resposta normal sense sessió no és vàlida', () async {
      await expectLater(
        _api(
          (_) async => _json({'sessionId': null, 'type': 'text', 'reply': 'x'}),
        ).sendMessage(token: 'tok', message: 'Hola'),
        throwsA(isA<ChatApiException>()),
      );
    });

    Future<ChatApiException> errorFor(
      int status,
      Map<String, Object?> body, {
      String? sessionId,
    }) async {
      try {
        await _api((_) async => _json(body, status))
            .sendMessage(token: 'tok', message: 'x', sessionId: sessionId);
      } on ChatApiException catch (e) {
        return e;
      }
      fail('Havia de llançar ChatApiException');
    }

    test('fa servir el codi del backend per al missatge', () async {
      final timeout = await errorFor(504, {
        'error': 'El servei de xatbot ha tardat massa a respondre',
        'code': 'CHATBOT_TIMEOUT',
      });
      expect(timeout.code, 'CHATBOT_TIMEOUT');
      expect(timeout.message, contains('ha tardat massa'));

      final events = await errorFor(503, {
        'error': 'El servei d\'esdeveniments no està disponible',
        'code': 'EVENTS_UNAVAILABLE',
      });
      expect(events.message, contains('esdeveniments'));

      final broken = await errorFor(502, {
        'error': 'El servei de xatbot ha fallat',
        'code': 'CHATBOT_ERROR',
      });
      expect(broken.message, contains('no està disponible'));

      final lost = await errorFor(404, {
        'error': 'Sessió de xat no trobada',
        'code': 'SESSION_NOT_FOUND',
      }, sessionId: 's1');
      expect(lost.isSessionLost, isTrue);
      expect(lost.message, contains('conversa ja no existeix'));
    });

    test('un 504 sense codi també és «ha tardat massa»', () async {
      final e = await errorFor(504, {'error': 'Gateway Timeout'});
      expect(e.code, isNull);
      expect(e.message, contains('ha tardat massa'));
    });
  });

  group('ChatController: tornar a provar una resposta alternativa', () {
    test('marca la resposta i, en reintentar, la substitueix', () async {
      final bodies = <Map<String, dynamic>>[];
      var call = 0;
      final chat = _controller((request) async {
        bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
        call++;
        return call == 1 ? _fallback() : _text('Et recomano un concert.');
      });
      addTearDown(chat.dispose);

      await chat.send('Concerts avui');
      final fallback = chat.messages.last;
      expect(fallback.isFallback, isTrue);
      expect(fallback.retryOf, chat.messages.first.id);
      expect(chat.sessionId, isNull);

      await chat.retryFallback(fallback.id);

      expect(chat.messages.map((m) => m.text), [
        'Concerts avui',
        'Et recomano un concert.',
      ]);
      expect(chat.messages.last.isFallback, isFalse);
      expect(chat.sessionId, 's1');
      expect(bodies.map((b) => b['message']), [
        'Concerts avui',
        'Concerts avui',
      ]);
    });

    test(
      'una resposta alternativa conserva la sessió que ja hi havia',
      () async {
        var call = 0;
        final chat = _controller((_) async {
          call++;
          return call == 1 ? _text('Hola!') : _fallback(session: 's1');
        });
        addTearDown(chat.dispose);

        await chat.send('Hola');
        await chat.send('I demà?');

        expect(chat.sessionId, 's1');
        expect(chat.messages.last.isFallback, isTrue);
      },
    );

    test('ignora ids que no són respostes alternatives', () async {
      final chat = _controller((_) async => _text('Hola!'));
      addTearDown(chat.dispose);

      await chat.send('Hola');
      await chat.retryFallback(chat.messages.last.id);

      expect(chat.messages, hasLength(2));
    });
  });

  group('Pantalla del xat', () {
    Future<void> pumpChat(WidgetTester tester, ChatController chat) async {
      await tester.pumpWidget(MaterialApp(home: ChatScreen(controller: chat)));
      await tester.pump();
      await tester.pump();
    }

    // L'indicador «escrivint» és una animació infinita (pumpAndSettle no
    // acabaria): es fan pumps curts fins que no queda cap petició en curs.
    Future<void> settleChat(WidgetTester tester, ChatController chat) async {
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        if (!chat.isTyping) break;
      }
      await tester.pump();
    }

    Future<void> sendFromInput(WidgetTester tester, String text) async {
      await tester.enterText(find.byKey(const ValueKey('chat-input')), text);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('chat-send')));
      await tester.pump();
    }

    testWidgets('mostra l\'avís i el botó, i en tornar-ho a provar respon', (
      tester,
    ) async {
      var call = 0;
      final chat = _controller((_) async {
        call++;
        return call == 1 ? _fallback() : _text('Et recomano un concert.');
      });
      addTearDown(chat.dispose);
      await pumpChat(tester, chat);

      await sendFromInput(tester, 'Concerts avui');
      await settleChat(tester, chat);

      expect(
        find.text('L\'assistent no ha pogut respondre del tot.'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('chat-fallback-retry')));
      await tester.pump();
      await settleChat(tester, chat);

      expect(find.text('Et recomano un concert.'), findsOneWidget);
      expect(
        find.text('L\'assistent no ha pogut respondre del tot.'),
        findsNothing,
      );
    });

    testWidgets('si ja hi ha missatges després, no es pot reintentar', (
      tester,
    ) async {
      var call = 0;
      final chat = _controller((_) async {
        call++;
        return call == 1 ? _fallback() : _text('Hola!');
      });
      addTearDown(chat.dispose);
      await pumpChat(tester, chat);

      await sendFromInput(tester, 'Concerts avui');
      await settleChat(tester, chat);
      await sendFromInput(tester, 'Hola');
      await settleChat(tester, chat);

      expect(
        find.text('L\'assistent no ha pogut respondre del tot.'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('chat-fallback-retry')), findsNothing);
    });
  });

  group('Mode demo: proves d\'errors', () {
    test(
      '«prova error» dona una resposta alternativa i després respon',
      () async {
        final api = DemoChatApi(latency: Duration.zero);

        final first = await api.sendMessage(
          token: 'demo',
          message: 'prova error',
        );
        final second = await api.sendMessage(
          token: 'demo',
          message: 'prova error',
        );

        expect(first.isFallback, isTrue);
        expect(second.isFallback, isFalse);
      },
    );

    test('«prova timeout» falla una vegada amb CHATBOT_TIMEOUT', () async {
      final api = DemoChatApi(latency: Duration.zero);

      await expectLater(
        api.sendMessage(token: 'demo', message: 'prova timeout'),
        throwsA(
          isA<ChatApiException>().having(
            (e) => e.code,
            'code',
            'CHATBOT_TIMEOUT',
          ),
        ),
      );
      final retry = await api.sendMessage(
        token: 'demo',
        message: 'prova timeout',
      );
      expect(retry.reply, isNotEmpty);
    });
  });
}
