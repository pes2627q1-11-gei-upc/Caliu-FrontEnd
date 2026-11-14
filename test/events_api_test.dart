import 'dart:convert';

import 'package:caliu/data/event.dart';
import 'package:caliu/data/event_query.dart';
import 'package:caliu/data/events_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _baseUrl = 'http://127.0.0.1:3000';

Map<String, dynamic> _eventJson({
  String id = 'evt-1',
  String title = 'Concert al Parc',
  double lng = 2.1734,
  double lat = 41.3851,
}) =>
    {
      'id': id,
      'title': title,
      'location': {
        'type': 'Point',
        'coordinates': [lng, lat],
      },
    };

String _pageBody({
  List<Map<String, dynamic>> items = const [],
  int page = 1,
  int limit = 20,
  int? total,
}) =>
    jsonEncode({
      'items': items,
      'page': page,
      'limit': limit,
      'total': total ?? items.length,
    });

void main() {
  group('EventsApi.fetchEvents', () {
    test('200 amb llista: converteix id, títol i coordenades GeoJSON', () async {
      final client = MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/events');
        return http.Response(
          _pageBody(items: [
            _eventJson(id: 'abc', title: 'Fira', lng: 2.15, lat: 41.40),
          ]),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final api = EventsApi(client: client, baseUrl: _baseUrl);

      final page = await api.fetchEvents(const EventQuery());

      expect(page.items, hasLength(1));
      expect(page.total, 1);
      final event = page.items.single;
      expect(event, isA<Event>());
      expect(event.id, 'abc');
      expect(event.title, 'Fira');
      expect(event.location, isNotNull);
      expect(event.location!.longitude, closeTo(2.15, 1e-9));
      expect(event.location!.latitude, closeTo(41.40, 1e-9));
    });

    test('200 amb llista buida: retorna items buits i total 0', () async {
      final client = MockClient(
        (_) async => http.Response(_pageBody(), 200),
      );
      final api = EventsApi(client: client, baseUrl: _baseUrl);

      final page = await api.fetchEvents(const EventQuery());

      expect(page.items, isEmpty);
      expect(page.total, 0);
      expect(page.page, 1);
    });

    test('500: llença EventsApiException amb el codi i el detall', () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({'error': 'fallada interna'}),
          500,
          headers: {'content-type': 'application/json'},
        ),
      );
      final api = EventsApi(client: client, baseUrl: _baseUrl);

      await expectLater(
        api.fetchEvents(const EventQuery()),
        throwsA(
          isA<EventsApiException>().having(
            (e) => e.message,
            'message',
            'API 500: fallada interna',
          ),
        ),
      );
    });

    test(
      '404: llença EventsApiException amb missatge de no trobat',
      () async {
        final client = MockClient(
          (_) async => http.Response('{}', 404),
        );
        final api = EventsApi(client: client, baseUrl: _baseUrl);

        // Comportament real: el 404 de _getJson sempre diu
        // "Esdeveniment no trobat", també a GET /events.
        await expectLater(
          api.fetchEvents(const EventQuery()),
          throwsA(
            isA<EventsApiException>().having(
              (e) => e.message,
              'message',
              'Esdeveniment no trobat',
            ),
          ),
        );
      },
    );

    test('JSON mal format amb 200: propaga FormatException', () async {
      final client = MockClient(
        (_) async => http.Response('no-és-json{', 200),
      );
      final api = EventsApi(client: client, baseUrl: _baseUrl);

      // jsonDecode després del 200 no es captura a _getJson.
      await expectLater(
        api.fetchEvents(const EventQuery()),
        throwsA(isA<FormatException>()),
      );
    });

    test(
      'envia a la URL els filtres reals: radi, dates, categoria i paginació',
      () async {
        late Uri seen;
        final from = DateTime(2026, 11, 14, 10);
        final to = DateTime(2026, 11, 15, 22);

        final client = MockClient((request) async {
          seen = request.url;
          return http.Response(_pageBody(), 200);
        });
        final api = EventsApi(client: client, baseUrl: _baseUrl);

        await api.fetchEvents(
          EventQuery(
            category: 'Música',
            lat: 41.4,
            lng: 2.2,
            radiusKm: 12.5,
            from: from,
            to: to,
            page: 2,
            limit: 10,
          ),
        );

        expect(seen.path, '/events');
        expect(seen.queryParameters['category'], 'Música');
        expect(seen.queryParameters['lat'], '41.4');
        expect(seen.queryParameters['lng'], '2.2');
        expect(seen.queryParameters['radiusKm'], '12.5');
        expect(seen.queryParameters['page'], '2');
        expect(seen.queryParameters['limit'], '10');
        expect(
          seen.queryParameters['from'],
          from.toUtc().toIso8601String(),
        );
        expect(
          seen.queryParameters['to'],
          to.toUtc().toIso8601String(),
        );
        // EventQuery no té filtre de preu: no ha d'aparèixer a la URL.
        expect(seen.queryParameters.containsKey('price'), isFalse);
      },
    );
  });

  group('EventsApi.fetchById', () {
    test('200: retorna l’esdeveniment amb id, títol i coordenades', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/events/evt-9');
        return http.Response(
          jsonEncode(_eventJson(id: 'evt-9', title: 'Teatre', lng: 1.1, lat: 42.0)),
          200,
        );
      });
      final api = EventsApi(client: client, baseUrl: _baseUrl);

      final event = await api.fetchById('evt-9');

      expect(event.id, 'evt-9');
      expect(event.title, 'Teatre');
      expect(event.location!.longitude, closeTo(1.1, 1e-9));
      expect(event.location!.latitude, closeTo(42.0, 1e-9));
    });

    test('404: llença EventsApiException de no trobat', () async {
      final client = MockClient(
        (_) async => http.Response('{"error":"missing"}', 404),
      );
      final api = EventsApi(client: client, baseUrl: _baseUrl);

      await expectLater(
        api.fetchById('inexistent'),
        throwsA(
          isA<EventsApiException>().having(
            (e) => e.message,
            'message',
            'Esdeveniment no trobat',
          ),
        ),
      );
    });
  });

  group('EventsApi.fetchNearby', () {
    test('passa lat, lng, radi i limit a la petició /events', () async {
      late Uri seen;
      final client = MockClient((request) async {
        seen = request.url;
        return http.Response(
          _pageBody(items: [_eventJson()]),
          200,
        );
      });
      final api = EventsApi(client: client, baseUrl: _baseUrl);

      final items = await api.fetchNearby(
        lat: 41.39,
        lng: 2.17,
        radiusKm: 8,
        limit: 25,
      );

      expect(items, hasLength(1));
      expect(items.single.id, 'evt-1');
      // Documenta el path real: avui va a /events (no a /events/nearby).
      expect(seen.path, '/events');
      expect(seen.queryParameters['lat'], '41.39');
      expect(seen.queryParameters['lng'], '2.17');
      expect(seen.queryParameters['radiusKm'], '8.0');
      expect(seen.queryParameters['limit'], '25');
    });
  });
}
