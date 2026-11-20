import 'package:caliu/data/events_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'consulta el catàleg i normalitza espais sense inventar localitats',
    () async {
      final api = EventsApi(
        client: MockClient((request) async {
          expect(request.url.path, '/events/locations');
          return http.Response(
            '{"locations":[{"comarca":" Garrotxa ","municipality":" Olot "},{"comarca":"","municipality":""}]}',
            200,
          );
        }),
      );
      final rows = await api.fetchLocations();
      expect(rows.length, 1);
      expect(rows.single.comarca, 'Garrotxa');
      expect(rows.single.municipality, 'Olot');
    },
  );
  test('accepta un catàleg buit', () async {
    final api = EventsApi(
      client: MockClient((_) async => http.Response('{"locations":[]}', 200)),
    );
    expect(await api.fetchLocations(), isEmpty);
  });
  test('no amaga un endpoint absent ni un catàleg malformat', () async {
    for (final response in [
      http.Response('{}', 404),
      http.Response('{"locations":null}', 200),
    ]) {
      final api = EventsApi(client: MockClient((_) async => response));
      await expectLater(
        api.fetchLocations(),
        throwsA(isA<EventsApiException>()),
      );
    }
  });
}
