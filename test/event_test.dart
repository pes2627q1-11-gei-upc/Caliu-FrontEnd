import 'package:caliu/data/event.dart';
import 'package:caliu/data/event_query.dart';
import 'package:caliu/data/events_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('Event.fromJson', () {
    test('parseja GeoJSON [lng, lat] i camps bàsics', () {
      final event = Event.fromJson({
        'id': 'abc',
        'title': 'Concert',
        'venue': 'Sala',
        'municipality': 'Barcelona',
        'categories': ['Música'],
        'url': 'https://example.com',
        'images': ['https://example.com/a.jpg'],
        'location': {
          'type': 'Point',
          'coordinates': [2.17, 41.38],
        },
        'distanceMeters': 1200,
      });

      expect(event.id, 'abc');
      expect(event.title, 'Concert');
      expect(event.categories, ['Música']);
      expect(event.url, 'https://example.com');
      expect(event.imageUrl, 'https://example.com/a.jpg');
      expect(event.location?.latitude, closeTo(41.38, 0.001));
      expect(event.location?.longitude, closeTo(2.17, 0.001));
      expect(event.distanceMeters, 1200);
      expect(event.placeLine, contains('Sala'));
    });

    test('tolera JSON mínim sense location', () {
      final event = Event.fromJson({'id': '1'});
      expect(event.title, 'Sense títol');
      expect(event.hasLocation, isFalse);
      expect(event.images, isEmpty);
    });
  });

  group('EventQuery', () {
    test('toQueryParameters omet radi si no hi ha lat/lng', () {
      final q = EventQuery(q: 'farinera', radiusKm: 50, page: 2);
      final params = q.toQueryParameters();
      expect(params['q'], 'farinera');
      expect(params['page'], '2');
      expect(params.containsKey('radiusKm'), isFalse);
      expect(params.containsKey('lat'), isFalse);
    });

    test('inclou lat/lng i radi quan hi són', () {
      final q = EventQuery(lat: 41.4, lng: 2.1, radiusKm: 15);
      final params = q.toQueryParameters();
      expect(params['lat'], '41.4');
      expect(params['lng'], '2.1');
      expect(params['radiusKm'], anyOf('15', '15.0'));
    });
  });

  group('EventsApi.fetchHealth', () {
    test('ok quan /health respon 200', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/health');
        return http.Response(
          '{"status":"ok","service":"api-node"}',
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final api = EventsApi(
        client: client,
        baseUrl: 'http://127.0.0.1:3000',
      );
      final health = await api.fetchHealth();
      expect(health.ok, isTrue);
      expect(health.service, 'api-node');
      expect(health.baseUrl, 'http://127.0.0.1:3000');
    });

    test('no ok si la xarxa falla', () async {
      final client = MockClient((request) async {
        throw Exception('connection refused');
      });
      final api = EventsApi(client: client, baseUrl: 'http://127.0.0.1:3000');
      final health = await api.fetchHealth();
      expect(health.ok, isFalse);
      expect(health.error, isNotNull);
    });
  });
}
