import 'package:caliu/data/event.dart';
import 'package:caliu/data/map_event_markers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

Event _event({required String id, String title = 'Acte', LatLng? location}) =>
    Event(id: id, title: title, location: location);

void main() {
  group('shouldClusterAtZoom', () {
    test('agrupa només per sota del llindar', () {
      expect(shouldClusterAtZoom(kStopClusteringZoom - 0.1), isTrue);
      expect(shouldClusterAtZoom(kStopClusteringZoom), isFalse);
      expect(shouldClusterAtZoom(kStopClusteringZoom + 1), isFalse);
    });
  });

  group('buildEventMarkerSet (#114)', () {
    for (final cluster in [false, true]) {
      test('popup conserva el lloc i el callback (cluster: $cluster)', () {
        final opened = <Event>[];
        const event = Event(
          id: 'popup',
          title: 'Concert',
          venue: 'Teatre Principal',
          municipality: 'Olot',
          location: LatLng(42.18, 2.49),
        );
        final set = buildEventMarkerSet(
          [event],
          clusterGeneration: 1,
          cluster: cluster,
          onTap: (_) {},
          onInfoWindowTap: opened.add,
        );
        final popup = set.markers.single.infoWindow;
        expect(popup.title, event.title);
        expect(popup.snippet, '${event.shortPlace} ↗');
        popup.onTap!();
        expect(opened, [event]);
      });

      test('popup sense lloc ofereix Google Maps (cluster: $cluster)', () {
        final set = buildEventMarkerSet(
          [_event(id: 'empty', location: const LatLng(42, 2))],
          clusterGeneration: 1,
          cluster: cluster,
          onTap: (_) {},
        );
        expect(set.markers.single.infoWindow.snippet, 'Obrir a Google Maps ↗');
      });
    }

    test('amb cluster: vincula els pins al ClusterManager', () {
      final tapped = <String>[];
      final set = buildEventMarkerSet(
        [
          _event(id: 'a', location: const LatLng(41.4, 2.1)),
          _event(id: 'b'),
          _event(
            id: 'c',
            title: 'Concert',
            location: const LatLng(41.41, 2.11),
          ),
        ],
        clusterGeneration: 3,
        cluster: true,
        onTap: (e) => tapped.add(e.id),
      );

      expect(set.markers, hasLength(2));
      final expectedId = eventClusterManagerId(3);
      expect(set.clusterManagers.single.clusterManagerId, expectedId);
      expect(
        set.markers.every((m) => m.clusterManagerId == expectedId),
        isTrue,
      );
      expect(set.clusterManagers.single.onClusterTap, isNull);
      set.markers.singleWhere((m) => m.markerId.value == 'c').onTap!();
      expect(tapped, ['c']);
    });

    test('amb cluster: enllaça onClusterTap al ClusterManager (#115)', () {
      Cluster? tapped;
      final set = buildEventMarkerSet(
        [
          _event(id: 'a', location: const LatLng(41.4, 2.1)),
          _event(id: 'c', location: const LatLng(41.41, 2.11)),
        ],
        clusterGeneration: 2,
        cluster: true,
        onTap: (_) {},
        onClusterTap: (cluster) => tapped = cluster,
      );

      expect(set.clusterManagers.single.onClusterTap, isNotNull);
      final sample = Cluster(
        eventClusterManagerId(2),
        const [MarkerId('a'), MarkerId('c')],
        position: const LatLng(41.405, 2.105),
        bounds: LatLngBounds(
          southwest: const LatLng(41.4, 2.1),
          northeast: const LatLng(41.41, 2.11),
        ),
      );
      set.clusterManagers.single.onClusterTap!(sample);
      expect(tapped, sample);
    });

    test('sense cluster: pins individuals (dissolve anticipat)', () {
      final set = buildEventMarkerSet(
        [
          _event(id: 'a', location: const LatLng(41.4, 2.1)),
          _event(id: 'c', location: const LatLng(41.41, 2.11)),
        ],
        clusterGeneration: 1,
        cluster: false,
        onTap: (_) {},
      );

      expect(set.clusterManagers, isEmpty);
      expect(set.markers, hasLength(2));
      expect(set.markers.every((m) => m.clusterManagerId == null), isTrue);
    });

    test('llista buida → sense markers ni ClusterManager', () {
      final set = buildEventMarkerSet(
        const [],
        clusterGeneration: 1,
        cluster: true,
        onTap: (_) {},
      );
      expect(set.markers, isEmpty);
      expect(set.clusterManagers, isEmpty);
    });
  });

  group('focusForClusterTap (#115)', () {
    final spreadBounds = LatLngBounds(
      southwest: const LatLng(41.38, 2.15),
      northeast: const LatLng(41.40, 2.18),
    );
    final samePoint = const LatLng(41.39, 2.16);
    final degenerateBounds = LatLngBounds(
      southwest: samePoint,
      northeast: samePoint,
    );

    test('bounds amb span → enquadra el grup', () {
      final focus = focusForClusterTap(
        bounds: spreadBounds,
        position: const LatLng(41.39, 2.165),
        currentZoom: 11,
      );
      expect(focus, isA<ClusterTapFitBounds>());
      final fit = focus as ClusterTapFitBounds;
      expect(fit.bounds, spreadBounds);
      expect(fit.paddingPx, kClusterTapPaddingPx);
    });

    test('pins coincidents → centra i puja el zoom', () {
      final focus = focusForClusterTap(
        bounds: degenerateBounds,
        position: samePoint,
        currentZoom: 12,
      );
      expect(focus, isA<ClusterTapZoomTo>());
      final zoomTo = focus as ClusterTapZoomTo;
      expect(zoomTo.center, samePoint);
      expect(zoomTo.zoom, 12 + kClusterTapZoomStep);
    });

    test('pins coincidents al zoom màxim → no fa res', () {
      final focus = focusForClusterTap(
        bounds: degenerateBounds,
        position: samePoint,
        currentZoom: kMapMaxZoom,
      );
      expect(focus, isA<ClusterTapNoop>());
    });

    test('currentZoom per sobre del màxim no petar (decimals càmera)', () {
      final focus = focusForClusterTap(
        bounds: degenerateBounds,
        position: samePoint,
        currentZoom: kMapMaxZoom + 0.0000001,
      );
      expect(focus, isA<ClusterTapNoop>());
    });

    test('clusterBoundsAreUsable distingeix span real', () {
      expect(clusterBoundsAreUsable(spreadBounds), isTrue);
      expect(clusterBoundsAreUsable(degenerateBounds), isFalse);
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
