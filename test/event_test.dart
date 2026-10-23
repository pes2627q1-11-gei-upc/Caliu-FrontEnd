import 'package:caliu/data/event.dart';
import 'package:caliu/data/event_query.dart';
import 'package:flutter_test/flutter_test.dart';

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
      const q = EventQuery(lat: 41.4, lng: 2.1, radiusKm: 15);
      final params = q.toQueryParameters();
      expect(params['lat'], '41.4');
      expect(params['lng'], '2.1');
      expect(params['radiusKm'], '15.0');
    });
  });
}
