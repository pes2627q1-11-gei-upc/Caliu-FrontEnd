import 'dart:convert';

import 'package:caliu/data/event.dart';
import 'package:caliu/event_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _launcher = MethodChannel('plugins.flutter.io/url_launcher');
const _eventJson = {
  'id': 'concert',
  'title': 'Música & dansa',
  'venue': 'Plaça Major',
  'municipality': 'Vic',
  'startDate': '2026-11-30T18:30:00+01:00',
  'endDate': '2026-11-30T20:00:00+01:00',
};

Future<void> _openEvent(WidgetTester tester, Map<String, Object?> json) async {
  await http.runWithClient(
    () async {
      await tester.pumpWidget(
        const MaterialApp(home: EventDetailScreen(eventId: 'concert')),
      );
      await tester.pumpAndSettle();
    },
    () => MockClient(
      (_) async => http.Response(
        jsonEncode(json),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      ),
    ),
  );
}

void main() {
  test('l’enllaç inclou el títol, el lloc i les dates en UTC', () {
    final uri = Event.fromJson(_eventJson).googleCalendarUri!;

    expect(uri.scheme, 'https');
    expect(uri.host, 'calendar.google.com');
    expect(uri.path, '/calendar/r/eventedit');
    expect(uri.queryParameters, {
      'action': 'TEMPLATE',
      'text': 'Música & dansa',
      'dates': '20261130T173000Z/20261130T190000Z',
      'stz': 'Europe/Madrid',
      'etz': 'Europe/Madrid',
      'location': 'Plaça Major, Vic',
    });
  });

  test('sense un interval vàlid no genera un esborrany', () {
    for (final dates in [
      {'startDate': null},
      {'endDate': null},
      {'endDate': '2026-11-30T17:00:00+01:00'},
    ]) {
      expect(
        Event.fromJson({..._eventJson, ...dates}).googleCalendarUri,
        isNull,
      );
    }
  });

  testWidgets('el botó obre l’esborrany de Google Calendar', (tester) async {
    MethodCall? launch;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_launcher, (
      call,
    ) async {
      launch = call;
      return true;
    });
    await _openEvent(tester, _eventJson);

    await tester.tap(find.text('Afegir al calendari'));
    await tester.pumpAndSettle();

    expect(launch?.method, 'launch');
    expect(
      launch?.arguments['url'],
      Event.fromJson(_eventJson).googleCalendarUri.toString(),
    );
  });

  testWidgets('la fitxa sense data de fi amaga el botó', (tester) async {
    await _openEvent(tester, {..._eventJson, 'endDate': null});

    expect(find.text('Música & dansa'), findsOneWidget);
    expect(find.text('Afegir al calendari'), findsNothing);
  });
}
