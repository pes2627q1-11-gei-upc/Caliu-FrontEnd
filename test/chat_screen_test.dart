import 'dart:async';
import 'dart:convert';

import 'package:caliu/chat_screen.dart';
import 'package:caliu/data/chat_api.dart';
import 'package:caliu/data/chat_controller.dart';
import 'package:caliu/data/event.dart';
import 'package:caliu/widgets/chat/chat_event_card.dart';
import 'package:caliu/widgets/chat/typing_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'chat_test_helpers.dart';

Future<ChatController> _pump(
  WidgetTester tester,
  Future<http.Response> Function(http.Request) handler, {
  String? token = 'tok',
  void Function(BuildContext, Event)? openEvent,
  Future<bool?> Function(BuildContext)? openLogin,
  MemorySession? session,
}) async {
  final chat = ChatController(
    api: ChatApi(client: MockClient(handler), baseUrl: 'http://api.test'),
    session: session ?? MemorySession(token),
  );
  addTearDown(chat.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: ChatScreen(
        controller: chat,
        openEvent: openEvent,
        openLogin: openLogin,
      ),
    ),
  );
  // checkSession() llegeix el token de manera asíncrona.
  await tester.pump();
  await tester.pump();
  return chat;
}

void main() {
  testWidgets('sense sessió mostra el botó d\'iniciar sessió', (tester) async {
    final session = MemorySession();
    await _pump(
      tester,
      (_) async => http.Response('{}', 200),
      session: session,
      openLogin: (_) async {
        session.token = 'nou';
        return true;
      },
    );

    expect(find.text('Inicia sessió per parlar amb l\'assistent'), findsOneWidget);

    await tester.tap(find.text('Inicia sessió'));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('chat-input')), findsOneWidget);
    expect(find.text('Hola! Sóc l\'assistent de Caliu'), findsOneWidget);
  });

  testWidgets(
    'envia un missatge, mostra "escrivint" i després la resposta amb targeta',
    (tester) async {
      final pending = Completer<http.Response>();
      Event? opened;
      await _pump(
        tester,
        (_) => pending.future,
        openEvent: (_, event) => opened = event,
      );

      // El botó d'enviar està desactivat sense text.
      final send = find.byKey(const ValueKey('chat-send'));
      expect(tester.widget<IconButton>(send).onPressed, isNull);

      await tester.enterText(
        find.byKey(const ValueKey('chat-input')),
        'Concerts aquest cap de setmana',
      );
      await tester.pump();
      await tester.tap(send);
      await tester.pump();

      expect(find.text('Concerts aquest cap de setmana'), findsOneWidget);
      expect(find.byType(TypingIndicator), findsOneWidget);
      // El camp es buida en enviar.
      expect(
        tester.widget<TextField>(find.byKey(const ValueKey('chat-input'))).controller!.text,
        isEmpty,
      );

      pending.complete(
        http.Response(
          jsonEncode({
            'sessionId': 's1',
            'reply': 'Et recomano aquest concert.',
            'events': [eventJson],
          }),
          200,
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.byType(TypingIndicator), findsNothing);
      expect(find.text('Et recomano aquest concert.'), findsOneWidget);
      expect(find.byType(ChatEventCard), findsOneWidget);
      expect(find.text('Concert al Parc'), findsOneWidget);

      await tester.tap(find.byType(ChatEventCard));
      await tester.pump();
      expect(opened?.id, 'evt-1');
    },
  );

  testWidgets('un suggeriment s\'envia directament', (tester) async {
    final bodies = <String>[];
    await _pump(tester, (request) async {
      bodies.add(request.body);
      return http.Response('{"sessionId":"s1","reply":"Ok"}', 200);
    });

    await tester.tap(find.text(ChatScreen.suggestions.first));
    await tester.pump();
    await tester.pump();

    expect(jsonDecode(bodies.single)['message'], ChatScreen.suggestions.first);
    expect(find.text('Ok'), findsOneWidget);
  });

  testWidgets('un error mostra l\'avís i permet tornar a provar', (tester) async {
    var fail = true;
    await _pump(tester, (_) async {
      if (fail) return http.Response('{}', 503);
      return http.Response('{"sessionId":"s1","reply":"Ara sí"}', 200);
    });

    await tester.enterText(find.byKey(const ValueKey('chat-input')), 'Hola');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('chat-send')));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('no està disponible'), findsOneWidget);
    expect(find.text('No enviat · Tornar a provar'), findsOneWidget);

    fail = false;
    await tester.tap(find.text('No enviat · Tornar a provar'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Ara sí'), findsOneWidget);
    expect(find.text('No enviat · Tornar a provar'), findsNothing);
  });
}
