import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'event.dart';

/// Prefix de l'id del [ClusterManager] (#114).
///
/// A cada càrrega es regenera l'id (`caliu-events-1`, `caliu-events-2`, …)
/// perquè el plugin natiu netegi clústers buits que, si només es buiden els
/// markers, poden quedar dibuixats a la pantalla.
const String kEventClusterManagerIdPrefix = 'caliu-events';

ClusterManagerId eventClusterManagerId(int generation) =>
    ClusterManagerId('$kEventClusterManagerIdPrefix-$generation');

/// Resultat d'aplicar una càrrega de pins (markers + managers).
class EventMarkerSet {
  const EventMarkerSet({required this.markers, required this.clusterManagers});

  final Set<Marker> markers;
  final Set<ClusterManager> clusterManagers;
}

/// Construeix markers + ClusterManager per a una generació de càrrega.
///
/// Sense `onClusterTap`: el zoom en tocar un clúster és la #115.
/// Si no hi ha events amb ubicació, retorna conjunts buits (treu el manager
/// perquè no quedi un clúster fantasma).
EventMarkerSet buildEventMarkerSet(
  Iterable<Event> events, {
  required int clusterGeneration,
  required void Function(Event event) onTap,
}) {
  final withLocation = events.where((event) => event.hasLocation).toList();
  if (withLocation.isEmpty) {
    return const EventMarkerSet(markers: {}, clusterManagers: {});
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
            // Només el títol: la resta va a la previsualització (#154 / #44).
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
