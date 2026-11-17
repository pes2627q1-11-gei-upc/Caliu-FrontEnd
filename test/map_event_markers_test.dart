import 'package:caliu/data/event.dart';
import 'package:caliu/data/map_event_markers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

Event _event({required String id, String title = 'Acte', LatLng? location}) =>
    Event(id: id, title: title, location: location);

void main() {
  group('buildEventMarkerSet (#114)', () {
    test(
      'només inclou esdeveniments amb ubicació i els vincula al ClusterManager',
      () {
        final tapped = <String>[];
        final set = buildEventMarkerSet(
          [
            _event(id: 'a', location: const LatLng(41.4, 2.1)),
            _event(id: 'b'), // sense ubicació → no surt
            _event(
              id: 'c',
              title: 'Concert',
              location: const LatLng(41.41, 2.11),
            ),
          ],
          clusterGeneration: 3,
          onTap: (e) => tapped.add(e.id),
        );

        expect(set.markers, hasLength(2));
        expect(set.markers.map((m) => m.markerId.value).toSet(), {'a', 'c'});
        final expectedId = eventClusterManagerId(3);
        expect(set.clusterManagers.single.clusterManagerId, expectedId);
        expect(
          set.markers.every((m) => m.clusterManagerId == expectedId),
          isTrue,
        );
        // Sense onClusterTap: la #115 afegirà el zoom.
        expect(set.clusterManagers.single.onClusterTap, isNull);

        set.markers.singleWhere((m) => m.markerId.value == 'c').onTap!();
        expect(tapped, ['c']);
      },
    );

    test('una recàrrega amb nova generació substitueix ids (sense antics ni duplicats)', () {
      final first = buildEventMarkerSet(
        [
          _event(id: 'old', location: const LatLng(41.4, 2.1)),
          _event(id: 'keep', location: const LatLng(41.41, 2.11)),
        ],
        clusterGeneration: 1,
        onTap: (_) {},
      );
      final second = buildEventMarkerSet(
        [
          _event(id: 'keep', location: const LatLng(41.41, 2.11)),
          _event(id: 'new', location: const LatLng(41.42, 2.12)),
        ],
        clusterGeneration: 2,
        onTap: (_) {},
      );

      expect(first.markers.map((m) => m.markerId.value).toSet(), {
        'old',
        'keep',
      });
      expect(second.markers.map((m) => m.markerId.value).toSet(), {
        'keep',
        'new',
      });
      expect(
        first.clusterManagers.single.clusterManagerId,
        isNot(second.clusterManagers.single.clusterManagerId),
      );
    });

    test(
      'llista buida → sense markers ni ClusterManager (evita clúster fantasma)',
      () {
        final set = buildEventMarkerSet(
          const [],
          clusterGeneration: 1,
          onTap: (_) {},
        );
        expect(set.markers, isEmpty);
        expect(set.clusterManagers, isEmpty);
      },
    );
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
