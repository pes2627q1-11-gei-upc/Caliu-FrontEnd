import 'dart:convert';

import 'package:caliu/data/chat_api.dart';
import 'package:caliu/data/chat_controller.dart';
import 'package:caliu/data/chat_dates.dart';
import 'package:caliu/data/chat_filters.dart';
import 'package:caliu/data/chat_locale.dart';
import 'package:caliu/data/chat_message.dart';
import 'package:caliu/data/chat_plan.dart';
import 'package:caliu/data/event.dart';
import 'package:caliu/widgets/chat/chat_bubble.dart';
import 'package:caliu/widgets/chat/chat_filters_row.dart';
import 'package:caliu/widgets/chat/chat_itinerary_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'chat_test_helpers.dart';

/// Divendres 20 de novembre de 2026 al matí.
final _now = DateTime(2026, 11, 20, 10);

const _planJson = {
  'date': '2026-11-21',
  'steps': [
    {
      'order': 2,
      'id': 'evt-2',
      'title': 'Concert vermut',
      'start': '2026-11-21T12:30:00+01:00',
      'end': '2026-11-21T13:30:00+01:00',
      'venue': '',
      'address': '',
      'municipality': 'Girona',
      'coordinates': [2.824, 41.9845],
      'distanceKm': 0.4,
      'travelMinutes': 5,
      'url': '',
    },
    {
      'order': 1,
      'id': 'evt-1',
      'title': 'Visita guiada al Call',
      'start': '2026-11-21T10:30:00+01:00',
      'end': '2026-11-21T12:00:00+01:00',
      'venue': 'Call jueu',
      'address': '',
      'municipality': 'Girona',
      'coordinates': [2.8259, 41.9875],
      'distanceKm': null,
      'travelMinutes': null,
      'url': 'https://example.cat/call',
    },
  ],
};

ChatApi _api(Future<http.Response> Function(http.Request) handler) =>
    ChatApi(client: MockClient(handler), baseUrl: 'http://api.test');

String _local(String iso) => chatTime(DateTime.parse(iso).toLocal());

void main() {
  group('ChatFilters (tasca #138)', () {
    test('sense filtres o amb un format inesperat és null', () {
      expect(ChatFilters.fromJson(null), isNull);
      expect(ChatFilters.fromJson('tarda'), isNull);
      expect(
        ChatFilters.fromJson({
          'from': null,
          'to': null,
          'timeOfDay': null,
          'categories': [],
          'audience': null,
          'maxPrice': null,
        }),
        isNull,
      );
    });

    test('etiquetes: dia, franja, categoria, públic, preu i lloc', () {
      final filters = ChatFilters.fromJson({
        'from': '2026-11-20T15:00:00+01:00',
        'to': '2026-11-20T20:00:00+01:00',
        'timeOfDay': 'tarda',
        'categories': ['Música'],
        'audience': 'infantil',
        'maxPrice': 0,
        'municipality': 'Girona',
      })!;

      expect(filters.labels(_now), [
        'Avui',
        'Tarda',
        'Música',
        'Infantil',
        'Gratuït',
        'Girona',
      ]);
    });

    test('demà, cap de setmana, rang de dies i data passada', () {
      List<String> labels(Map<String, dynamic> json) =>
          ChatFilters.fromJson(json)!.labels(_now);

      expect(
        labels({
          'from': '2026-11-21T10:00:00+01:00',
          'to': '2026-11-21T12:00:00+01:00',
        }),
        ['Demà'],
      );
      expect(
        labels({
          'from': '2026-11-21T10:00:00+01:00',
          'to': '2026-11-22T20:00:00+01:00',
        }),
        ['Cap de setmana'],
      );
      expect(
        labels({
          'from': '2026-11-24T10:00:00+01:00',
          'to': '2026-11-26T20:00:00+01:00',
        }),
        ['Del 24 de novembre al 26 de novembre'],
      );
      expect(
        labels({
          'from': '2026-11-25T10:00:00+01:00',
          'to': '2026-11-25T12:00:00+01:00',
        }),
        ['Dimecres 25 de novembre'],
      );
      expect(labels({'datePassed': true}), ['Data ja passada']);
    });

    test('preu màxim, comarca i valors desconeguts', () {
      expect(
        ChatFilters.fromJson({
          'maxPrice': 15,
          'comarca': 'Gironès',
          'timeOfDay': 'matinada',
        })!.labels(_now),
        ['Matinada', 'Fins a 15 €', 'Gironès'],
      );
      expect(
        ChatFilters.fromJson({'maxPrice': 7.5})!.labels(_now),
        ['Fins a 7,50 €'],
      );
    });
  });

  group('ChatPlan (tasca #141)', () {
    test('llegeix els passos en ordre i en fa esdeveniments', () {
      final plan = ChatPlan.fromJson(_planJson)!;

      expect(plan.steps.map((s) => s.title), [
        'Visita guiada al Call',
        'Concert vermut',
      ]);
      expect(plan.date, DateTime(2026, 11, 21));
      final first = plan.steps.first;
      expect(first.place, 'Call jueu, Girona');
      expect(first.distanceKm, isNull);
      expect(first.location?.latitude, 41.9875);
      expect(first.location?.longitude, 2.8259);
      expect(plan.steps.last.place, 'Girona');
      expect(plan.steps.last.travelMinutes, 5);

      final event = first.toEvent();
      expect(event.id, 'evt-1');
      expect(event.title, 'Visita guiada al Call');
      expect(event.url, 'https://example.cat/call');
      expect(event.startDate, DateTime.parse('2026-11-21T10:30:00+01:00'));
    });

    test('ruta a peu a Google Maps entre els passos amb coordenades', () {
      final uri = ChatPlan.fromJson(_planJson)!.directionsUri!;
      expect(uri.host, 'www.google.com');
      expect(uri.path, '/maps/dir/');
      expect(uri.queryParameters['origin'], '41.9875,2.8259');
      expect(uri.queryParameters['destination'], '41.9845,2.824');
      expect(uri.queryParameters['travelmode'], 'walking');
      expect(uri.queryParameters.containsKey('waypoints'), isFalse);
    });

    test('un pla sense passos vàlids és null; sense id no s\'obre', () {
      expect(ChatPlan.fromJson(null), isNull);
      expect(ChatPlan.fromJson({'steps': []}), isNull);
      expect(
        ChatPlan.fromJson({
          'steps': [
            {'order': 1},
          ],
        }),
        isNull,
      );
      final plan = ChatPlan.fromJson({
        'steps': [
          {'order': 1, 'title': 'Passeig', 'id': null, 'coordinates': null},
        ],
      })!;
      expect(plan.steps.single.canOpen, isFalse);
      expect(plan.directionsUri, isNull);
    });
  });

  group('appChatLocale (tasca #147)', () {
    test('primer idioma del dispositiu que entén el xatbot', () {
      expect(appChatLocale(const [Locale('es', 'ES')]), 'es');
      expect(appChatLocale(const [Locale('fr'), Locale('en', 'GB')]), 'en');
      expect(appChatLocale(const [Locale('fr')]), 'ca');
      expect(appChatLocale(const []), 'ca');
    });
  });

  group('ChatApi: idioma, filtres i itinerari', () {
    test('envia el locale i llegeix filtres i pla', () async {
      late Map<String, dynamic> body;
      final api = _api((request) async {
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'sessionId': 's1',
            'type': 'plan',
            'reply': 'Aquí tens un itinerari:\n1. Visita\n2. Concert',
            'events': [],
            'filters': {'timeOfDay': 'tarda', 'categories': []},
            'plan': _planJson,
          }),
          200,
        );
      });

      final reply = await api.sendMessage(
        token: 'tok',
        message: 'Fes-me un pla',
        locale: 'es',
      );

      expect(body, {'message': 'Fes-me un pla', 'locale': 'es'});
      expect(reply.filters?.timeOfDay, 'tarda');
      expect(reply.plan?.steps, hasLength(2));
    });

    test('sense type "plan" s\'ignora el pla', () async {
      final api = _api(
        (_) async => http.Response(
          jsonEncode({
            'sessionId': 's1',
            'type': 'text',
            'reply': 'Hola',
            'plan': _planJson,
          }),
          200,
        ),
      );
      final reply = await api.sendMessage(token: 'tok', message: 'Hola');
      expect(reply.plan, isNull);
      expect(reply.filters, isNull);
    });

    test('si el backend no accepta el locale (400), es reintenta sense', () async {
      final bodies = <Map<String, dynamic>>[];
      final api = _api((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        bodies.add(body);
        if (body.containsKey('locale')) {
          return http.Response('{"error":"Cos de la petició no vàlid"}', 400);
        }
        return http.Response('{"sessionId":"s1","reply":"Hola"}', 200);
      });

      final reply = await api.sendMessage(
        token: 'tok',
        message: 'Hola',
        locale: 'ca',
      );

      expect(reply.reply, 'Hola');
      expect(bodies, [
        {'message': 'Hola', 'locale': 'ca'},
        {'message': 'Hola'},
      ]);
    });
  });

  test('el controlador envia l\'idioma i desa filtres i pla', () async {
    final bodies = <Map<String, dynamic>>[];
    final chat = ChatController(
      api: _api((request) async {
        bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
        return http.Response(
          jsonEncode({
            'sessionId': 's1',
            'type': 'plan',
            'reply': 'Pla',
            'filters': {'audience': 'familiar'},
            'plan': _planJson,
          }),
          200,
        );
      }),
      session: MemorySession('tok'),
      locale: () => 'en',
    );
    addTearDown(chat.dispose);

    await chat.send('Plan for tomorrow');

    expect(bodies.single['locale'], 'en');
    final answer = chat.messages.last;
    expect(answer.role, ChatRole.assistant);
    expect(answer.filters?.audience, 'familiar');
    expect(answer.plan?.steps, hasLength(2));
    // En reintentar, la còpia conserva filtres i pla.
    expect(answer.copyWith().plan, same(answer.plan));
    expect(answer.copyWith().filters, same(answer.filters));
  });

  group('Bombolla amb filtres i itinerari', () {
    Future<void> pumpBubble(
      WidgetTester tester,
      ChatMessage message, {
      ValueChanged<Event>? onOpenEvent,
      Future<void> Function(Uri)? onOpenRoute,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ChatBubble(
                message: message,
                now: _now,
                onOpenEvent: onOpenEvent ?? (_) {},
                onOpenRoute: onOpenRoute,
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('mostra els filtres interpretats sota la resposta', (
      tester,
    ) async {
      await pumpBubble(
        tester,
        ChatMessage(
          id: 'a1',
          role: ChatRole.assistant,
          text: 'Et recomano un taller.',
          filters: ChatFilters.fromJson({
            'from': '2026-11-20T15:00:00+01:00',
            'to': '2026-11-20T20:00:00+01:00',
            'timeOfDay': 'tarda',
            'audience': 'infantil',
            'maxPrice': 0,
          }),
        ),
      );

      expect(find.byType(ChatFiltersRow), findsOneWidget);
      expect(find.text('He entès:'), findsOneWidget);
      for (final label in ['Avui', 'Tarda', 'Infantil', 'Gratuït']) {
        expect(find.text(label), findsOneWidget);
      }
    });

    testWidgets('un missatge de l\'usuari no mostra filtres', (tester) async {
      await pumpBubble(
        tester,
        ChatMessage(
          id: 'u1',
          role: ChatRole.user,
          text: 'Hola',
          filters: ChatFilters.fromJson({'timeOfDay': 'tarda'}),
        ),
      );
      expect(find.byType(ChatFiltersRow), findsNothing);
    });

    testWidgets(
      'itinerari: passos en ordre, desplaçament, fitxa i ruta',
      (tester) async {
        Event? opened;
        Uri? route;
        await pumpBubble(
          tester,
          ChatMessage(
            id: 'a1',
            role: ChatRole.assistant,
            text: 'Aquí tens un itinerari de 2 passos:\n1. Visita\n2. Concert',
            plan: ChatPlan.fromJson(_planJson),
          ),
          onOpenEvent: (event) => opened = event,
          onOpenRoute: (uri) async => route = uri,
        );

        // De la resposta només queda la introducció.
        expect(find.text('Aquí tens un itinerari de 2 passos:'), findsOneWidget);
        expect(find.textContaining('1. Visita'), findsNothing);

        expect(find.byType(ChatItineraryCard), findsOneWidget);
        expect(find.text('Itinerari'), findsOneWidget);
        expect(find.text('Demà · 2 parades'), findsOneWidget);
        expect(find.text('Visita guiada al Call'), findsOneWidget);
        expect(find.text('Call jueu, Girona'), findsOneWidget);
        expect(
          find.text(
            '${_local('2026-11-21T10:30:00+01:00')} – '
            '${_local('2026-11-21T12:00:00+01:00')}',
          ),
          findsOneWidget,
        );
        expect(find.text('400 m · 5 min a peu'), findsOneWidget);

        final first = tester.getTopLeft(find.text('Visita guiada al Call'));
        final second = tester.getTopLeft(find.text('Concert vermut'));
        expect(first.dy, lessThan(second.dy));

        await tester.tap(find.text('Concert vermut'));
        await tester.pump();
        expect(opened?.id, 'evt-2');
        expect(opened?.title, 'Concert vermut');

        await tester.tap(find.byKey(const ValueKey('plan-route')));
        await tester.pump();
        expect(route?.queryParameters['travelmode'], 'walking');
      },
    );
  });
}
