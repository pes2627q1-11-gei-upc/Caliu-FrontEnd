import 'package:caliu/data/event.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

Event _event({
  String? venue,
  String? address,
  String? municipality,
  String? comarca,
  LatLng? location,
}) => Event(
  id: 'evt-1',
  title: 'Exposició',
  venue: venue,
  address: address,
  municipality: municipality,
  comarca: comarca,
  location: location,
);

void main() {
  group('Event.shortPlace (popup del marcador)', () {
    test('espai i municipi', () {
      final e = _event(
        venue: 'MEAM, Museu Europeu d\'Art Modern',
        address: 'C. de la Barra de Ferro, 5, 08003 Barcelona',
        municipality: 'Barcelona',
      );
      expect(e.shortPlace, 'MEAM, Museu Europeu d\'Art Modern, Barcelona');
    });

    test('sense espai fa servir l\'adreça', () {
      final e = _event(
        address: 'Rambla d\'Ègara, 340',
        municipality: 'Terrassa',
      );
      expect(e.shortPlace, 'Rambla d\'Ègara, 340, Terrassa');
    });

    test('no repeteix el municipi si ja hi és', () {
      final e = _event(
        address: 'C. de la Barra de Ferro, 5, 08003 Barcelona',
        municipality: 'Barcelona',
      );
      expect(e.shortPlace, 'C. de la Barra de Ferro, 5, 08003 Barcelona');
    });

    test('només municipi o comarca', () {
      expect(_event(municipality: 'Reus').shortPlace, 'Reus');
      expect(_event(comarca: 'Baix Camp').shortPlace, 'Baix Camp');
    });

    test('ignora camps en blanc i sense dades retorna buit', () {
      expect(
        _event(venue: '  ', municipality: ' Girona ').shortPlace,
        'Girona',
      );
      expect(_event().shortPlace, isEmpty);
    });
  });

  group('Event.googleMapsUri', () {
    test('enllaç de cerca de Google Maps amb les coordenades', () {
      final uri = _event(location: const LatLng(41.3851, 2.1734))
          .googleMapsUri!;
      expect(uri.scheme, 'https');
      expect(uri.host, 'www.google.com');
      expect(uri.path, '/maps/search/');
      expect(uri.queryParameters['api'], '1');
      expect(uri.queryParameters['query'], '41.3851,2.1734');
    });

    test('sense coordenades retorna null', () {
      expect(_event().googleMapsUri, isNull);
    });
  });

  group('Event.googleMapsDirectionsUri', () {
    test('prioritza les coordenades i deixa l’origen obert', () {
      final uri = _event(
        location: const LatLng(41.3851, 2.1734),
        address: 'Carrer Major, 5',
      ).googleMapsDirectionsUri!;

      expect(uri.scheme, 'https');
      expect(uri.host, 'www.google.com');
      expect(uri.path, '/maps/dir/');
      expect(uri.queryParameters, {
        'api': '1',
        'destination': '41.3851,2.1734',
      });
    });

    test('sense coordenades fa servir l’adreça i el municipi', () {
      final uri = _event(
        address: ' Rambla d’Ègara, 340 ',
        municipality: 'Terrassa',
      ).googleMapsDirectionsUri!;

      expect(
        uri.queryParameters['destination'],
        'Rambla d’Ègara, 340, Terrassa',
      );
    });

    test('permet indicar un recinte amb nom', () {
      final uri = _event(
        venue: 'Teatre Principal',
        municipality: 'Olot',
      ).googleMapsDirectionsUri!;

      expect(uri.queryParameters['destination'], 'Teatre Principal, Olot');
    });

    test('un municipi sol no identifica la destinació', () {
      final event = _event(venue: ' ', address: ' ', municipality: 'Reus');
      expect(event.googleMapsDirectionsUri, isNull);
    });
  });
}
