import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'event.dart';

/// Prefix de l'id del [ClusterManager] (#114).
const String kEventClusterManagerIdPrefix = 'caliu-events';

/// A partir d'aquest zoom (inclòs) es mostren pins individuals.
/// El ClusterManager natiu no exposa `maxZoom`/`minClusterSize`; sense això
/// els clústers es mantenen massa temps en apropar el mapa.
const double kStopClusteringZoom = 13.5;

/// Zoom màxim del mapa (ha de coincidir amb [MinMaxZoomPreference] a MapView).
const double kMapMaxZoom = 18;

/// Padding (px) en enquadrar els bounds d'un clúster (#115).
const double kClusterTapPaddingPx = 64;

/// Increment de zoom si els pins del clúster coincideixen (#115).
const double kClusterTapZoomStep = 2;

/// Span mínim perquè [LatLngBounds] sigui usable amb `newLatLngBounds`.
const double kClusterBoundsMinSpan = 1e-5;

ClusterManagerId eventClusterManagerId(int generation) =>
    ClusterManagerId('$kEventClusterManagerIdPrefix-$generation');

bool shouldClusterAtZoom(double zoom) => zoom < kStopClusteringZoom;

/// True si els bounds del clúster cobreixen una àrea real (no pins coincidents).
bool clusterBoundsAreUsable(LatLngBounds bounds) {
  final latSpan = (bounds.northeast.latitude - bounds.southwest.latitude).abs();
  final lngSpan = (bounds.northeast.longitude - bounds.southwest.longitude)
      .abs();
  return latSpan >= kClusterBoundsMinSpan || lngSpan >= kClusterBoundsMinSpan;
}

/// Com apropar la càmera en tocar un clúster (#115).
///
/// Amb bounds útils → enquadrar. Amb coordenades coincidents → centrar i
/// pujar el zoom. Si ja som al zoom màxim i no hi ha span → no fer res.
sealed class ClusterTapFocus {
  const ClusterTapFocus();
}

/// Enquadra tots els pins del clúster.
final class ClusterTapFitBounds extends ClusterTapFocus {
  const ClusterTapFitBounds({
    required this.bounds,
    this.paddingPx = kClusterTapPaddingPx,
  });

  final LatLngBounds bounds;
  final double paddingPx;
}

/// Centra i aplica un zoom concret (pins coincidents).
final class ClusterTapZoomTo extends ClusterTapFocus {
  const ClusterTapZoomTo({required this.center, required this.zoom});

  final LatLng center;
  final double zoom;
}

/// Cap animació (p. ex. ja al zoom màxim amb pins al mateix punt).
final class ClusterTapNoop extends ClusterTapFocus {
  const ClusterTapNoop();
}

/// Decideix el focus de càmera a partir de les dades del [Cluster] de l'SDK.
ClusterTapFocus focusForClusterTap({
  required LatLngBounds bounds,
  required LatLng position,
  required double currentZoom,
  double maxZoom = kMapMaxZoom,
  double paddingPx = kClusterTapPaddingPx,
  double zoomStep = kClusterTapZoomStep,
}) {
  if (clusterBoundsAreUsable(bounds)) {
    return ClusterTapFitBounds(bounds: bounds, paddingPx: paddingPx);
  }
  final nextZoom = (currentZoom + zoomStep).clamp(currentZoom, maxZoom);
  if (nextZoom <= currentZoom + 0.05) {
    return const ClusterTapNoop();
  }
  return ClusterTapZoomTo(center: position, zoom: nextZoom);
}

/// Resultat d'aplicar una càrrega de pins (markers + managers).
class EventMarkerSet {
  const EventMarkerSet({required this.markers, required this.clusterManagers});

  final Set<Marker> markers;
  final Set<ClusterManager> clusterManagers;
}

/// Construeix markers (+ ClusterManager si [cluster] és true).
///
/// [onClusterTap]: apropar la càmera al grup (#115). Android/iOS/web
/// (MarkerClusterer) exposen el mateix callback amb `bounds` + `position`.
/// Llista buida → conjunts buits (treu el manager; evita clúster fantasma).
EventMarkerSet buildEventMarkerSet(
  Iterable<Event> events, {
  required int clusterGeneration,
  required bool cluster,
  required void Function(Event event) onTap,
  void Function(Event event)? onInfoWindowTap,
  void Function(Cluster cluster)? onClusterTap,
}) {
  final withLocation = events.where((event) => event.hasLocation).toList();
  if (withLocation.isEmpty) {
    return const EventMarkerSet(markers: {}, clusterManagers: {});
  }

  final managerId = eventClusterManagerId(clusterGeneration);
  return EventMarkerSet(
    clusterManagers: cluster
        ? {
            ClusterManager(
              clusterManagerId: managerId,
              onClusterTap: onClusterTap,
            ),
          }
        : const {},
    markers: withLocation
        .map(
          (event) => Marker(
            markerId: MarkerId(event.id),
            position: event.location!,
            clusterManagerId: cluster ? managerId : null,
            infoWindow: InfoWindow(
              title: event.title,
              snippet: event.shortPlace.isEmpty
                  ? 'Obrir a Google Maps ↗'
                  : '${event.shortPlace} ↗',
              onTap: onInfoWindowTap == null
                  ? null
                  : () => onInfoWindowTap(event),
            ),
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
