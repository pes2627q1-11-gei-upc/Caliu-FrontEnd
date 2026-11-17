import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'event.dart';

/// Prefix de l'id del [ClusterManager] (#114).
const String kEventClusterManagerIdPrefix = 'caliu-events';

/// A partir d'aquest zoom (inclòs) es mostren pins individuals.
/// El ClusterManager natiu no exposa `maxZoom`/`minClusterSize`; sense això
/// els clústers es mantenen massa temps en apropar el mapa.
const double kStopClusteringZoom = 13.5;

ClusterManagerId eventClusterManagerId(int generation) =>
    ClusterManagerId('$kEventClusterManagerIdPrefix-$generation');

bool shouldClusterAtZoom(double zoom) => zoom < kStopClusteringZoom;

/// Resultat d'aplicar una càrrega de pins (markers + managers).
class EventMarkerSet {
  const EventMarkerSet({required this.markers, required this.clusterManagers});

  final Set<Marker> markers;
  final Set<ClusterManager> clusterManagers;
}

/// Construeix markers (+ ClusterManager si [cluster] és true).
///
/// Sense `onClusterTap`: el zoom en tocar un clúster és la #115.
/// Llista buida → conjunts buits (treu el manager; evita clúster fantasma).
EventMarkerSet buildEventMarkerSet(
  Iterable<Event> events, {
  required int clusterGeneration,
  required bool cluster,
  required void Function(Event event) onTap,
}) {
  final withLocation = events.where((event) => event.hasLocation).toList();
  if (withLocation.isEmpty) {
    return const EventMarkerSet(markers: {}, clusterManagers: {});
  }

  if (!cluster) {
    return EventMarkerSet(
      clusterManagers: const {},
      markers: withLocation
          .map(
            (event) => Marker(
              markerId: MarkerId(event.id),
              position: event.location!,
              infoWindow: InfoWindow(title: event.title),
              onTap: () => onTap(event),
            ),
          )
          .toSet(),
    );
  }

  final managerId = eventClusterManagerId(clusterGeneration);
  return EventMarkerSet(
    clusterManagers: {ClusterManager(clusterManagerId: managerId)},
    markers: withLocation
        .map(
          (event) => Marker(
            markerId: MarkerId(event.id),
            position: event.location!,
            clusterManagerId: managerId,
            infoWindow: InfoWindow(title: event.title),
            onTap: () => onTap(event),
          ),
        )
        .toSet(),
  );
}

/// Indexa només esdeveniments amb coordenades (els que poden ser pins).
Map<String, Event> indexEventsWithLocation(Iterable<Event> events) {
  return {
    for (final event in events.where((e) => e.hasLocation)) event.id: event,
  };
}

/// Després d'una recàrrega: manté la previsualització només si l'esdeveniment
/// continua present; si no, la neteja.
Event? selectionAfterReload(Event? selected, Map<String, Event> byId) {
  if (selected == null) return null;
  return byId[selected.id];
}
