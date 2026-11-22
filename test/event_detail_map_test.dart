import 'dart:convert';

import 'package:caliu/event_detail_screen.dart';
import 'package:caliu/widgets/event_preview_card.dart';
import 'package:caliu/widgets/map_event_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Future<void> _showEvent(
  WidgetTester tester, {
  required bool hasLocation,
}) async {
  await http.runWithClient(
    () async {
      await tester.pumpWidget(
        const MaterialApp(home: EventDetailScreen(eventId: 'evt-1')),
      );
      await tester.pumpAndSettle();
    },
    () => MockClient(
      (_) async => http.Response(
        jsonEncode({
          'id': 'evt-1',
          'title': 'Concert',
          'venue': 'Teatre Principal',
          if (hasLocation)
            'location': {
              'coordinates': [2.1734, 41.3851],
            },
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      ),
    ),
  );
}

void main() {
  testWidgets('Veure al mapa centra l’esdeveniment i selecciona el marcador', (
    tester,
  ) async {
    const geolocator = MethodChannel('flutter.baseflow.com/geolocator');
    var locationCalls = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(geolocator, (
      _,
    ) async {
      locationCalls++;
      return false;
    });
    await _showEvent(tester, hasLocation: true);

    await tester.tap(find.text('Veure al mapa'));
    await tester.pumpAndSettle();

    final map = tester.widget<GoogleMap>(find.byType(GoogleMap));
    final preview = tester.widget<MapEventPreview>(
      find.byType(MapEventPreview),
    );
    const location = LatLng(41.3851, 2.1734);

    expect(map.initialCameraPosition.target, location);
    expect(map.markers.single.position, location);
    expect(map.markers.single.markerId, const MarkerId('evt-1'));
    expect(preview.selected?.id, 'evt-1');
    expect(locationCalls, 0);

    await tester.tap(find.byKey(EventPreviewCard.openButtonKey));
    await tester.pumpAndSettle();
    expect(find.byType(GoogleMap), findsNothing);
    expect(find.byType(EventDetailScreen), findsOneWidget);
  });

  testWidgets('enrere torna a la fitxa amb la previsualització oberta', (
    tester,
  ) async {
    await _showEvent(tester, hasLocation: true);
    await tester.tap(find.text('Veure al mapa'));
    await tester.pumpAndSettle();
    expect(find.byType(EventPreviewCard), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byType(GoogleMap), findsNothing);
    expect(find.byType(EventDetailScreen), findsOneWidget);
  });

  testWidgets('sense coordenades el botó Veure al mapa no apareix', (
    tester,
  ) async {
    await _showEvent(tester, hasLocation: false);

    expect(find.text('Teatre Principal'), findsOneWidget);
    expect(find.text('Veure al mapa'), findsNothing);
  });
}
