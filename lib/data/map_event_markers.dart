import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'event.dart';

/// #114: un sol [ClusterManager] per als pins d'esdeveniments.
///
/// Sense `onClusterTap`: el zoom en tocar un clúster és la tasca germana #115.
/// Amb el callback a null, el plugin no fa zoom automàtic (només ignora el toc
/// a nivell Flutter); el nombre del grup el pinta l'SDK natiu.
const ClusterManagerId kEventClusterManagerId = ClusterManagerId(
  'caliu-events',
);

/// Managers passats a [GoogleMap.clusterManagers].
Set<ClusterManager> eventClusterManagers() => {
  const ClusterManager(clusterManagerId: kEventClusterManagerId),
};

/// Indexa només esdeveniments amb coordenades (els que poden ser pins).
Map<String, Event> indexEventsWithLocation(Iterable<Event> events) {
  return {
    for (final event in events.where((e) => e.hasLocation)) event.id: event,
  };
}

/// Construeix els [Marker]s agrupables. Substitueix el conjunt sencer a cada
/// càrrega per evitar duplicats o pins antics.
Set<Marker> markersForEvents(
  Iterable<Event> events, {
  required void Function(Event event) onTap,
}) {
  return events
      .where((event) => event.hasLocation)
      .map(
        (event) => Marker(
          markerId: MarkerId(event.id),
          position: event.location!,
          clusterManagerId: kEventClusterManagerId,
          // Només el títol: la resta va a la previsualització (#154 / #44).
          infoWindow: InfoWindow(title: event.title),
          onTap: () => onTap(event),
        ),
      )
      .toSet();
}

/// Després d'una recàrrega: manté la previsualització només si l'esdeveniment
/// continua present; si no, la neteja.
Event? selectionAfterReload(Event? selected, Map<String, Event> byId) {
  if (selected == null) return null;
  return byId[selected.id];
}
