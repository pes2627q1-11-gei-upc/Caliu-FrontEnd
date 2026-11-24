import 'dart:async';
import 'dart:convert';

import 'package:caliu/chat_history_screen.dart';
import 'package:caliu/chat_screen.dart';
import 'package:caliu/data/chat_api.dart';
import 'package:caliu/data/chat_controller.dart';
import 'package:caliu/data/chat_demo.dart';
import 'package:caliu/data/chat_message.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'chat_test_helpers.dart';

/// Tests de "Nova conversa" (tasca #162, H.U #47) i de l'historial de
/// converses (tasca #164, H.U #48).

typedef _Handler = Future<http.Response> Function(http.Request);

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status);

const _sessionsJson = {
  'items': [
    {
      'id': 's2',
      'title': 'plans per avui a Girona?',
      'createdAt': '2026-11-23T09:00:00.000Z',
      'lastActivityAt': '2026-11-23T09:05:12.000Z',
    },
    {
      'id': 's-buida',
      'title': null,
      'createdAt': '2026-11-22T18:30:00.000Z',
      'lastActivityAt': '2026-11-22T18:30:00.000Z',
    },
    {
      'id': 's1',
      'title': 'concerts gratuïts',
      'createdAt': '2026-11-20T10:00:00.000Z',
      'lastActivityAt': '2026-11-20T10:01:00.000Z',
    },
  ],
};

Map<String, Object> _messagesJson(String prefix) => {
  'items': [
    {
      'id': '${prefix}1',
      'role': 'user',
      'content': 'Pregunta $prefix',
      'createdAt': '2026-11-23T09:05:10.000Z',
    },
    {
      'id': '${prefix}2',
      'role': 'assistant',
      'content': 'Resposta $prefix',
      'createdAt': '2026-11-23T09:05:12.000Z',
    },
  ],
};

http.Response _reply(String reply, {String session = 's-nova'}) =>
    _json({'sessionId': session, 'type': 'text', 'reply': reply});

/// Backend fals: respon segons el mètode i la ruta, i desa les peticions.
class _Backend {
  _Backend({this.sessions = const {'items': []}, this.onCreate});

  Object sessions;
  _Handler? onCreate;
  final requests = <http.Request>[];

  List<String> get routes => [
    for (final r in requests) '${r.method} ${r.url.path}',
  ];

  List<Map<String, dynamic>> get sentMessages => [
    for (final r in requests)
      if (r.url.path == '/chat/messages')
        jsonDecode(r.body) as Map<String, dynamic>,
  ];

  Future<http.Response> handle(http.Request request) async {
    requests.add(request);
    final path = request.url.path;
    if (request.method == 'GET' && path == '/chat/sessions') {
      return _json(sessions);
    }
    if (request.method == 'GET' && path.startsWith('/chat/sessions/')) {
      final id = path.split('/')[3];
      if (id == 'perduda') {
        return _json({
          'error': 'Sessió de xat no trobada',
          'code': 'SESSION_NOT_FOUND',
        }, 404);
      }
      return _json(_messagesJson(id));
    }
    if (request.method == 'POST' && path == '/chat/sessions') {
      final create = onCreate;
      if (create != null) return create(request);
      return _json({
        'sessionId': 's-nova',
        'createdAt': '2026-11-24T21:00:00.000Z',
      }, 201);
    }
    if (request.method == 'POST' && path == '/chat/messages') {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      return _reply(
        'Resposta a ${body['message']}',
        session: body['sessionId'] as String? ?? 's-nova',
      );
    }
    return http.Response('{}', 404);
  }

  ChatApi api() =>
      ChatApi(client: MockClient(handle), baseUrl: 'http://api.test');

  ChatController controller([MemorySession? session]) =>
      ChatController(api: api(), session: session ?? MemorySession('tok'));
}

void main() {
  group('ChatApi: sessions del xat', () {
    test('createSession fa POST /chat/sessions amb un cos buit', () async {
      final backend = _Backend();

      final id = await backend.api().createSession(token: 'tok');

      expect(id, 's-nova');
      final request = backend.requests.single;
      expect(request.method, 'POST');
      expect(request.url.path, '/chat/sessions');
      expect(request.headers['Authorization'], 'Bearer tok');
      expect(jsonDecode(request.body), <String, Object>{});
    });

    test('createSession: un 429 és un error amb el missatge del servidor', () {
      final backend = _Backend(
        onCreate: (_) async =>
            _json({'error': 'Massa peticions', 'code': 'RATE_LIMITED'}, 429),
      );

      expect(
        backend.api().createSession(token: 'tok'),
        throwsA(
          isA<ChatApiException>()
              .having((e) => e.statusCode, 'statusCode', 429)
              .having((e) => e.message, 'message', 'Massa peticions'),
        ),
      );
    });

    test('createSession sense sessionId és una resposta inesperada', () {
      final backend = _Backend(onCreate: (_) async => _json({}, 201));

      expect(
        backend.api().createSession(token: 'tok'),
        throwsA(isA<ChatApiException>()),
      );
    });

    test(
      'listSessions llegeix l\'historial i descarta els mal formats',
      () async {
        final backend = _Backend(
          sessions: {
            'items': [
              ..._sessionsJson['items']!,
              {'title': 'sense id'},
              'no és un objecte',
            ],
          },
        );

        final sessions = await backend.api().listSessions(token: 'tok');

        expect(sessions.map((s) => s.id), ['s2', 's-buida', 's1']);
        expect(sessions.first.title, 'plans per avui a Girona?');
        expect(
          sessions.first.lastActivityAt,
          DateTime.utc(2026, 11, 23, 9, 5, 12).toLocal(),
        );
        expect(sessions[1].isEmpty, isTrue);
        expect(backend.routes.single, 'GET /chat/sessions');
      },
    );

    test('listSessions sense `items` és una resposta inesperada', () {
      final backend = _Backend(sessions: {'sessions': []});

      expect(
        backend.api().listSessions(token: 'tok'),
        throwsA(isA<ChatApiException>()),
      );
    });

    test('fetchMessages llegeix els missatges en ordre', () async {
      final backend = _Backend();

      final messages = await backend.api().fetchMessages(
        token: 'tok',
        sessionId: 's2',
      );

      expect(backend.routes.single, 'GET /chat/sessions/s2/messages');
      expect(messages.map((m) => m.role), [ChatRole.user, ChatRole.assistant]);
      expect(messages.map((m) => m.text), ['Pregunta s2', 'Resposta s2']);
      expect(messages.first.id, 'hs21');
      expect(messages.every((m) => m.events.isEmpty), isTrue);
    });

    test('fetchMessages: una sessió que no existeix és una sessió perduda', () {
      final backend = _Backend();

      expect(
        backend.api().fetchMessages(token: 'tok', sessionId: 'perduda'),
        throwsA(
          isA<ChatApiException>()
              .having((e) => e.isSessionLost, 'isSessionLost', isTrue)
              .having((e) => e.statusCode, 'statusCode', 404),
        ),
      );
    });
  });

  group('ChatController: conversa anterior en entrar (#164)', () {
    test('reobre la sessió més recent amb els seus missatges', () async {
      final backend = _Backend(sessions: _sessionsJson);
      final chat = backend.controller();
      addTearDown(chat.dispose);

      await chat.checkSession();

      expect(chat.sessionId, 's2');
      expect(chat.messages.map((m) => m.text), ['Pregunta s2', 'Resposta s2']);
      expect(chat.loadingConversation, isFalse);

      // Els missatges nous continuen la mateixa sessió.
      await chat.send('I demà?');
      expect(backend.sentMessages.single['sessionId'], 's2');
    });

    test('si la més recent és buida, la reutilitza sense demanar-ne els '
        'missatges', () async {
      final backend = _Backend(
        sessions: {
          'items': [
            {'id': 's-buida', 'title': null},
          ],
        },
      );
      final chat = backend.controller();
      addTearDown(chat.dispose);

      await chat.checkSession();

      expect(chat.sessionId, 's-buida');
      expect(chat.messages, isEmpty);
      expect(backend.routes, ['GET /chat/sessions']);
    });

    test(
      'sense historial comença buit i el primer missatge crea la sessió',
      () async {
        final backend = _Backend();
        final chat = backend.controller();
        addTearDown(chat.dispose);

        await chat.checkSession();
        await chat.send('Hola');

        expect(backend.sentMessages.single.containsKey('sessionId'), isFalse);
        expect(chat.sessionId, 's-nova');
      },
    );

    test(
      'si no es pot recuperar, comença una conversa nova sense error',
      () async {
        final chat = ChatController(
          api: ChatApi(
            client: MockClient((_) async => http.Response('{}', 503)),
            baseUrl: 'http://api.test',
          ),
          session: MemorySession('tok'),
        );
        addTearDown(chat.dispose);

        await chat.checkSession();

        expect(chat.error, isNull);
        expect(chat.sessionId, isNull);
        expect(chat.messages, isEmpty);
        expect(chat.loadingConversation, isFalse);
      },
    );

    test('només es recupera una vegada per sessió d\'usuari', () async {
      final backend = _Backend(sessions: _sessionsJson);
      final chat = backend.controller();
      addTearDown(chat.dispose);

      await chat.checkSession();
      await chat.checkSession();

      expect(
        backend.routes.where((r) => r == 'GET /chat/sessions'),
        hasLength(1),
      );
    });

    test('escriure abans que acabi de carregar descarta la càrrega', () async {
      final pending = Completer<http.Response>();
      final backend = _Backend();
      final chat = ChatController(
        api: ChatApi(
          client: MockClient((request) {
            if (request.method == 'GET') return pending.future;
            return backend.handle(request);
          }),
          baseUrl: 'http://api.test',
        ),
        session: MemorySession('tok'),
      );
      addTearDown(chat.dispose);

      final check = chat.checkSession();
      await Future<void>.delayed(Duration.zero);
      expect(chat.loadingConversation, isTrue);

      await chat.send('Hola');
      expect(chat.loadingConversation, isFalse);

      pending.complete(_json(_sessionsJson));
      await check;

      expect(chat.sessionId, 's-nova');
      expect(chat.messages.map((m) => m.text), ['Hola', 'Resposta a Hola']);
    });

    test('si s\'entra amb un altre token, es torna a recuperar', () async {
      final backend = _Backend(sessions: _sessionsJson);
      final session = MemorySession('tok');
      final chat = backend.controller(session);
      addTearDown(chat.dispose);

      await chat.checkSession();
      await chat.send('Un missatge del primer compte');

      session.token = 'altre';
      backend.sessions = {'items': []};
      await chat.checkSession();

      expect(chat.messages, isEmpty);
      expect(chat.sessionId, isNull);
    });
  });

  group('ChatController: nova conversa (#162)', () {
    test(
      'crea una sessió, buida el xat i hi envia els missatges nous',
      () async {
        final backend = _Backend();
        final chat = backend.controller();
        addTearDown(chat.dispose);

        await chat.send('Hola');
        expect(chat.sessionId, 's-nova');

        backend.onCreate = (_) async =>
            _json({'sessionId': 's-neta', 'createdAt': 'x'}, 201);
        await chat.startNewConversation();

        expect(chat.messages, isEmpty);
        expect(chat.sessionId, 's-neta');
        expect(chat.creatingSession, isFalse);
        expect(backend.routes, contains('POST /chat/sessions'));

        await chat.send('Pregunta nova');
        expect(backend.sentMessages.last['sessionId'], 's-neta');
      },
    );

    test('amb el xat buit no crea cap sessió', () async {
      final backend = _Backend();
      final chat = backend.controller();
      addTearDown(chat.dispose);

      await chat.startNewConversation();

      expect(backend.requests, isEmpty);
    });

    test('si falla, buida el xat igualment i el backend en crearà una amb el '
        'primer missatge', () async {
      final backend = _Backend(onCreate: (_) async => http.Response('{}', 503));
      final chat = backend.controller();
      addTearDown(chat.dispose);

      await chat.send('Hola');
      await chat.startNewConversation();

      expect(chat.messages, isEmpty);
      expect(chat.sessionId, isNull);
      expect(chat.error, isNull);

      await chat.send('De nou');
      expect(backend.sentMessages.last.containsKey('sessionId'), isFalse);
    });

    test(
      'amb el token caducat demana iniciar sessió i conserva el xat',
      () async {
        final session = MemorySession('tok');
        final backend = _Backend(
          onCreate: (_) async => _json({'error': 'Token no vàlid'}, 401),
        );
        final chat = backend.controller(session);
        addTearDown(chat.dispose);

        await chat.send('Hola');
        await chat.startNewConversation();

        expect(chat.needsLogin, isTrue);
        expect(session.token, isNull);
        expect(chat.messages, hasLength(2));
        expect(chat.error, contains('Torna a iniciar sessió'));
      },
    );
  });

  group('ChatController: reobrir una conversa de l\'historial (#164)', () {
    test('substitueix els missatges i continua aquella sessió', () async {
      final backend = _Backend();
      final chat = backend.controller();
      addTearDown(chat.dispose);
      await chat.send('Hola');

      final opened = await chat.openSession('s1');

      expect(opened, isTrue);
      expect(chat.sessionId, 's1');
      expect(chat.messages.map((m) => m.text), ['Pregunta s1', 'Resposta s1']);

      await chat.send('I l\'endemà?');
      expect(backend.sentMessages.last['sessionId'], 's1');
    });

    test('la conversa actual no es torna a demanar', () async {
      final backend = _Backend();
      final chat = backend.controller();
      addTearDown(chat.dispose);
      await chat.send('Hola');
      backend.requests.clear();

      expect(await chat.openSession('s-nova'), isTrue);

      expect(backend.requests, isEmpty);
      expect(chat.messages, hasLength(2));
    });

    test(
      'una conversa que ja no existeix mostra un error i conserva el xat',
      () async {
        final backend = _Backend();
        final chat = backend.controller();
        addTearDown(chat.dispose);
        await chat.send('Hola');

        final opened = await chat.openSession('perduda');

        expect(opened, isFalse);
        expect(chat.error, 'Aquesta conversa ja no existeix.');
        expect(chat.sessionId, 's-nova');
        expect(chat.messages, hasLength(2));
      },
    );
  });

  group('Pantalla del xat', () {
    Future<ChatController> pumpChat(
      WidgetTester tester,
      _Backend backend,
    ) async {
      final chat = backend.controller();
      addTearDown(chat.dispose);
      await tester.pumpWidget(MaterialApp(home: ChatScreen(controller: chat)));
      await settle(tester);
      return chat;
    }

    IconButton button(WidgetTester tester, String key) =>
        tester.widget<IconButton>(find.byKey(ValueKey(key)));

    testWidgets(
      '«Nova conversa» només s\'activa amb missatges i buida el xat',
      (tester) async {
        final backend = _Backend();
        await pumpChat(tester, backend);

        expect(button(tester, 'chat-new').onPressed, isNull);
        expect(button(tester, 'chat-new').tooltip, 'Nova conversa');

        await tester.enterText(
          find.byKey(const ValueKey('chat-input')),
          'Hola',
        );
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('chat-send')));
        await settle(tester);
        expect(find.text('Resposta a Hola'), findsOneWidget);
        expect(button(tester, 'chat-new').onPressed, isNotNull);

        await tester.tap(find.byKey(const ValueKey('chat-new')));
        await settle(tester);

        expect(find.text('Resposta a Hola'), findsNothing);
        expect(find.text('Hola! Sóc l\'assistent de Caliu'), findsOneWidget);
        expect(
          find.text('Conversa nova. L\'anterior és a l\'historial.'),
          findsOneWidget,
        );
      },
    );

    testWidgets('en entrar mostra la conversa anterior', (tester) async {
      await pumpChat(tester, _Backend(sessions: _sessionsJson));

      expect(find.text('Pregunta s2'), findsOneWidget);
      expect(find.text('Resposta s2'), findsOneWidget);
    });

    testWidgets('l\'historial reobre la conversa triada', (tester) async {
      final backend = _Backend(sessions: _sessionsJson);
      final chat = await pumpChat(tester, backend);

      await tester.tap(find.byKey(const ValueKey('chat-history')));
      await tester.pumpAndSettle();

      expect(find.text('Historial de converses'), findsOneWidget);
      expect(find.text('plans per avui a Girona?'), findsOneWidget);
      expect(find.text('concerts gratuïts'), findsOneWidget);
      // Les sessions buides no surten a l'historial.
      expect(find.byKey(const ValueKey('chat-history-s-buida')), findsNothing);
      expect(find.textContaining('Conversa actual'), findsOneWidget);

      await tester.tap(find.text('concerts gratuïts'));
      await tester.pumpAndSettle();

      expect(chat.sessionId, 's1');
      expect(find.text('Pregunta s1'), findsOneWidget);
      expect(find.text('Pregunta s2'), findsNothing);
    });
  });

  group('Pantalla d\'historial', () {
    Future<void> pumpHistory(
      WidgetTester tester,
      Future<List<ChatSessionSummary>> Function() load,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChatHistoryScreen(
            loadSessions: load,
            now: () => DateTime(2026, 11, 23, 12),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('sense converses mostra un missatge informatiu', (
      tester,
    ) async {
      await pumpHistory(
        tester,
        () async => const [ChatSessionSummary(id: 'buida')],
      );

      expect(find.text('Encara no tens cap conversa'), findsOneWidget);
    });

    testWidgets('mostra el dia i l\'hora de l\'última activitat', (
      tester,
    ) async {
      await pumpHistory(
        tester,
        () async => [
          ChatSessionSummary(
            id: 's1',
            title: 'Concerts',
            lastActivityAt: DateTime(2026, 11, 23, 9, 5),
          ),
        ],
      );

      expect(find.text('Avui · 09:05'), findsOneWidget);
    });

    testWidgets('si falla, permet tornar-ho a provar', (tester) async {
      var calls = 0;
      await pumpHistory(tester, () async {
        calls++;
        if (calls == 1) {
          throw const ChatApiException('No s\'ha pogut connectar.');
        }
        return const [ChatSessionSummary(id: 's1', title: 'Concerts')];
      });

      expect(find.text('No s\'ha pogut carregar l\'historial'), findsOneWidget);

      await tester.tap(find.text('Torna-ho a provar'));
      await tester.pumpAndSettle();

      expect(find.text('Concerts'), findsOneWidget);
    });
  });

  test('mode demo: nova conversa i historial sense backend', () async {
    final api = DemoChatApi(latency: Duration.zero);
    final chat = ChatController(api: api, session: DemoChatSession());
    addTearDown(chat.dispose);

    await chat.checkSession();
    await chat.send('Què puc fer avui?');
    final first = chat.sessionId;
    await chat.startNewConversation();
    await chat.send('Una ruta per Girona');

    final sessions = await chat.loadSessions();
    expect(sessions.map((s) => s.title), [
      'Una ruta per Girona',
      'Què puc fer avui?',
    ]);

    expect(await chat.openSession(first!), isTrue);
    expect(chat.messages.first.text, 'Què puc fer avui?');
  });
}

/// Pumps curts fins que no queda cap petició en curs (la barra de càrrega és
/// una animació infinita i pumpAndSettle no acabaria mentre es veu).
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}
