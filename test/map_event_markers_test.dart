import 'package:caliu/data/event.dart';
import 'package:caliu/data/map_event_markers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

Event _event({required String id, String title = 'Acte', LatLng? location}) =>
    Event(id: id, title: title, location: location);

void main() {
  group('markersForEvents (#114)', () {
    test(
      'només inclou esdeveniments amb ubicació i els vincula al ClusterManager',
      () {
        final tapped = <String>[];
        final markers = markersForEvents([
          _event(id: 'a', location: const LatLng(41.4, 2.1)),
          _event(id: 'b'), // sense ubicació → no surt
          _event(
            id: 'c',
            title: 'Concert',
            location: const LatLng(41.41, 2.11),
          ),
        ], onTap: (e) => tapped.add(e.id));

        expect(markers, hasLength(2));
        expect(markers.map((m) => m.markerId.value).toSet(), {'a', 'c'});
        expect(
          markers.every((m) => m.clusterManagerId == kEventClusterManagerId),
          isTrue,
        );
        expect(
          eventClusterManagers().single.clusterManagerId,
          kEventClusterManagerId,
        );
        // Sense onClusterTap: la #115 afegirà el zoom.
        expect(eventClusterManagers().single.onClusterTap, isNull);

        markers.singleWhere((m) => m.markerId.value == 'c').onTap!();
        expect(tapped, ['c']);
      },
    );

    test(
      'una recàrrega substitueix el conjunt (sense ids antics ni duplicats)',
      () {
        final first = markersForEvents([
          _event(id: 'old', location: const LatLng(41.4, 2.1)),
          _event(id: 'keep', location: const LatLng(41.41, 2.11)),
        ], onTap: (_) {});
        final second = markersForEvents([
          _event(id: 'keep', location: const LatLng(41.41, 2.11)),
          _event(id: 'new', location: const LatLng(41.42, 2.12)),
        ], onTap: (_) {});

        expect(first.map((m) => m.markerId.value).toSet(), {'old', 'keep'});
        expect(second.map((m) => m.markerId.value).toSet(), {'keep', 'new'});
        expect(second.where((m) => m.markerId.value == 'keep'), hasLength(1));
      },
    );

    test('llista buida → cap marcador', () {
      expect(markersForEvents(const [], onTap: (_) {}), isEmpty);
    });
  });

  group('selectionAfterReload', () {
    test('manté la selecció si l’esdeveniment continua disponible', () {
      final selected = _event(id: 'a', location: const LatLng(41.4, 2.1));
      final byId = indexEventsWithLocation([
        selected,
        _event(id: 'b', location: const LatLng(41.5, 2.2)),
      ]);
      expect(selectionAfterReload(selected, byId)?.id, 'a');
    });

    test('neteja la selecció si el pin ja no hi és', () {
      final selected = _event(id: 'gone', location: const LatLng(41.4, 2.1));
      final byId = indexEventsWithLocation([
        _event(id: 'other', location: const LatLng(41.5, 2.2)),
      ]);
      expect(selectionAfterReload(selected, byId), isNull);
    });
  });
}
