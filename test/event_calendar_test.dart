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
  'url': 'https://agenda.cultura.gencat.cat/activitat?id=concert&lang=ca',
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
  test(
    'l’enllaç inclou el títol, el lloc, les dates UTC i l’enllaç oficial',
    () {
      final uri = Event.fromJson(_eventJson).googleCalendarUri!;

      expect(uri.scheme, 'https');
      expect(uri.host, 'calendar.google.com');
      expect(uri.path, '/calendar/render');
      expect(uri.queryParameters, {
        'action': 'TEMPLATE',
        'text': 'Música & dansa',
        'dates': '20261130T173000Z/20261130T190000Z',
        'stz': 'Europe/Madrid',
        'etz': 'Europe/Madrid',
        'location': 'Plaça Major, Vic',
        'details': _eventJson['url'],
      });
    },
  );

  test('omet els enllaços oficials que no són URL web vàlides', () {
    for (final url in [null, '', 'https://', 'javascript:void(0)']) {
      final uri = Event.fromJson({..._eventJson, 'url': url})
          .googleCalendarUri!;
      expect(uri.queryParameters, isNot(contains('details')));
    }
  });

  test('amb hora d’inici, proposa dues hores quan falta l’hora de fi', () {
    for (final endDate in [null, _eventJson['startDate']]) {
      final event = Event.fromJson({..._eventJson, 'endDate': endDate});
      expect(
        event.googleCalendarUri?.queryParameters['dates'],
        '20261130T173000Z/20261130T193000Z',
      );
    }
  });

  test('la mitjanit de Barcelona es publica com a dia sencer', () {
    // A l’hivern, 23.00 UTC és la mitjanit a Barcelona.
    final event = Event.fromJson({
      ..._eventJson,
      'startDate': '2026-11-29T23:00:00.000Z',
      'endDate': '2026-11-30T22:59:59.000Z',
    });

    expect(
      event.googleCalendarUri?.queryParameters['dates'],
      '20261130/20261201',
    );
  });

  test('un interval de dies conserva l’últim dia amb el canvi d’hora', () {
    final event = Event.fromJson({
      ..._eventJson,
      'startDate': '2026-03-28T23:00:00.000Z',
      'endDate': '2026-04-01T21:59:59.000Z',
    });

    expect(
      event.googleCalendarUri?.queryParameters['dates'],
      '20260329/20260402',
    );
  });

  test('un dia sencer sense data de fi ocupa només aquell dia', () {
    final event = Event.fromJson({
      ..._eventJson,
      'startDate': '2026-07-01T22:00:00.000Z',
      'endDate': null,
    });

    expect(
      event.googleCalendarUri?.queryParameters['dates'],
      '20260702/20260703',
    );
  });

  test('menys de catorze dies sencers conserva tot l’interval', () {
    final shorter = Event.fromJson({
      ..._eventJson,
      'startDate': '2026-11-29T23:00:00.000Z',
      'endDate': '2026-12-12T22:59:59.000Z',
    });

    expect(
      shorter.googleCalendarUri?.queryParameters['dates'],
      '20261130/20261213',
    );
  });

  test('a partir de catorze dies sencers només agafa el primer dia', () {
    final longer = Event.fromJson({
      ..._eventJson,
      'startDate': '2026-11-29T23:00:00.000Z',
      'endDate': '2026-12-13T22:59:59.000Z',
    });

    expect(
      longer.googleCalendarUri?.queryParameters['dates'],
      '20261130/20261201',
    );
  });

  test('una exposició amb hora i interval llarg només usa el primer dia', () {
    final event = Event.fromJson({
      ..._eventJson,
      'endDate': '2027-01-31T20:00:00+01:00',
    });

    expect(
      event.googleCalendarUri?.queryParameters['dates'],
      '20261130T173000Z/20261130T193000Z',
    );
  });

  test('sense un interval vàlid no genera un esborrany', () {
    for (final dates in [
      {'startDate': null},
      {'endDate': '2026-11-30T17:00:00+01:00'},
    ]) {
      expect(
        Event.fromJson({..._eventJson, ...dates}).googleCalendarUri,
        isNull,
      );
    }
  });

  testWidgets('el botó obre l’esborrany de Google Calendar sense data de fi', (
    tester,
  ) async {
    MethodCall? launch;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_launcher, (
      call,
    ) async {
      launch = call;
      return true;
    });
    final json = {..._eventJson, 'endDate': null};
    await _openEvent(tester, json);

    await tester.tap(find.text('Afegir al calendari'));
    await tester.pumpAndSettle();

    expect(launch?.method, 'launch');
    expect(
      launch?.arguments['url'],
      Event.fromJson(json).googleCalendarUri.toString(),
    );
  });

  testWidgets('la fitxa d’una exposició llarga mostra el botó del primer dia', (
    tester,
  ) async {
    MethodCall? launch;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_launcher, (
      call,
    ) async {
      launch = call;
      return true;
    });
    final json = {..._eventJson, 'endDate': '2027-01-31T20:00:00+01:00'};
    await _openEvent(tester, json);

    expect(find.text('Música & dansa'), findsOneWidget);
    expect(find.text('Afegir al calendari'), findsOneWidget);

    await tester.tap(find.text('Afegir al calendari'));
    await tester.pumpAndSettle();

    final expected = Event.fromJson(json).googleCalendarUri!;
    expect(
      expected.queryParameters['dates'],
      '20261130T173000Z/20261130T193000Z',
    );
    expect(launch?.method, 'launch');
    expect(launch?.arguments['url'], expected.toString());
  });

  testWidgets('la fitxa d’un esdeveniment curt també mostra el botó', (
    tester,
  ) async {
    await _openEvent(tester, _eventJson);

    expect(find.text('Afegir al calendari'), findsOneWidget);
  });
}
