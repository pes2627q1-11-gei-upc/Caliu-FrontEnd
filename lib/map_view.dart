import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'data/event.dart';
import 'data/search_radius.dart';
import 'data/events_api.dart';
import 'data/map_event_markers.dart';
import 'event_detail_screen.dart';
import 'search_screen.dart';
import 'theme/caliu_colors.dart';
import 'widgets/map_event_preview.dart';

/// Amaga POIs i etiquetes de llocs de Google (feedback demo: sense info externa).
const String _mapStyleNoPois = '''
[
  {"featureType":"poi","stylers":[{"visibility":"off"}]},
  {"featureType":"transit","stylers":[{"visibility":"off"}]}
]
''';

/// Marge fora de la finestra visible perquè els pins arribin abans de veure's.
const double _viewportMargin = 0.4;

/// Fallback quan no hi ha GPS / permís (Plaça Catalunya, BCN).
const LatLng _barcelona = LatLng(41.3851, 2.1734);

/// Límits aproximats de Catalunya (#117).
final LatLngBounds _cataloniaBounds = LatLngBounds(
  southwest: const LatLng(40.52, 0.15),
  northeast: const LatLng(42.86, 3.33),
);

enum _LocationMode {
  /// Centrat a la posició de l'usuari.
  user,

  /// Sense GPS usable: mostrem Barcelona.
  fallbackBarcelona,
}

class MapView extends StatefulWidget {
  const MapView({super.key, this.isActive = true, this.radius, this.eventsApi});

  /// Si la pestanya Mapa és la visible (el mapa continua muntat a l'`IndexedStack`).
  final bool isActive;
  final SearchRadius? radius;

  /// Injectable per als tests (MockClient); en producció usa l'API per defecte.
  final EventsApi? eventsApi;

  @override
  State<MapView> createState() => _MapViewState();
}

class _MapViewState extends State<MapView> {
  late final EventsApi _eventsApi = widget.eventsApi ?? EventsApi();
  late final SearchRadius _radius = widget.radius ?? SearchRadius();

  GoogleMapController? mapController;
  Set<Marker> _markers = {};
  Set<ClusterManager> _clusterManagers = {};

  /// #44: esdeveniment del marcador tocat (previsualització ràpida).
  Event? _selected;
  final Map<String, Event> _eventsById = {};

  bool _eventsRequestInFlight = false;
  bool _mapReadyToShow = false;
  bool _acceptCameraIdleReloads = false;
  bool _locating = false;

  LatLng _focus = _barcelona;
  _LocationMode _locationMode = _LocationMode.fallbackBarcelona;
  String? _locationBanner;
  bool _permissionDeniedForever = false;

  static const double _initialZoom = 14;

  CameraPosition? _lastCamera;
  LatLngBounds? _loadedBounds;
  double? _loadedZoom;
  Timer? _cameraIdleTimer;
  int _loadGeneration = 0;

  /// Generació del ClusterManager (es renova en passar a mode clúster).
  int _clusterGeneration = 0;
  bool _clusteringEnabled = true;

  /// En allunyar: força refresca a l'idle (zona visible més gran).
  bool _pendingWideReload = false;

  /// Zona on ja hem confirmat que no hi ha esdeveniments (evita bucle de fetch).
  LatLngBounds? _confirmedEmptyBounds;

  /// Evita dues animacions seguides si es toca el mateix clúster de pressa (#115).
  bool _clusterZoomInFlight = false;

  bool get _hasUserLocation => _locationMode == _LocationMode.user;

  @override
  void dispose() {
    _cameraIdleTimer?.cancel();
    _radius.removeListener(_radiusChanged);
    if (widget.radius == null) _radius.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _radius.addListener(_radiusChanged);
    unawaited(_bootstrap());
  }

  void _radiusChanged() {
    ++_loadGeneration;
    _loadedBounds = null;
    _loadedZoom = null;
    _confirmedEmptyBounds = null;
    setState(() {
      _markers = {};
      _clusterManagers = {};
      _selected = null;
      _eventsById.clear();
      _eventsRequestInFlight = false;
    });
    if (!_radius.locating) {
      unawaited(_showRadiusAndReload());
    }
  }

  Future<void> _showRadiusAndReload() async {
    final center = _radius.center;
    final km = _radius.radiusKm;
    if (center != null && km != null && mapController != null) {
      try {
        await mapController!.animateCamera(
          CameraUpdate.newLatLngBounds(_boundsAround(center, km), 32),
        );
      } catch (_) {
        // El mapa pot estar acabant de crear-se; el filtre continua actiu.
      }
    }
    if (mounted) await _reloadForVisibleRegion(force: true);
  }

  Future<void> _bootstrap() async {
    // Sense diàleg ni SnackBar: el banner ja informa; el diàleg surt al recentrar.
    await _resolveAndApplyFocus(requestIfNeeded: true);
    if (!mounted) return;
    setState(() => _mapReadyToShow = true);
  }

  /// #153: centra al GPS si es pot; si es denega el permís, Barcelona + banner.
  Future<void> _resolveAndApplyFocus({required bool requestIfNeeded}) async {
    setState(() => _locating = true);
    try {
      final result = await _resolveFocus(requestIfNeeded: requestIfNeeded);
      if (!mounted) return;
      setState(() {
        _focus = result.focus;
        _locationMode = result.mode;
        _locationBanner = result.banner;
        _permissionDeniedForever = result.deniedForever;
        _locating = false;
      });

      await _moveCameraToFocus();
    } finally {
      if (mounted && _locating) {
        setState(() => _locating = false);
      }
    }
  }

  Future<
    ({LatLng focus, _LocationMode mode, String? banner, bool deniedForever})
  >
  _resolveFocus({required bool requestIfNeeded}) async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return (
          focus: _barcelona,
          mode: _LocationMode.fallbackBarcelona,
          banner: 'Els serveis d\'ubicació estan desactivats.',
          deniedForever: false,
        );
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied && requestIfNeeded) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied) {
        return (
          focus: _barcelona,
          mode: _LocationMode.fallbackBarcelona,
          banner: 'Permís d\'ubicació denegat. Pots activar-lo amb el botó d\'ubicació.',
          deniedForever: false,
        );
      }

      if (permission == LocationPermission.deniedForever) {
        return (
          focus: _barcelona,
          mode: _LocationMode.fallbackBarcelona,
          banner: 'Permís d\'ubicació bloquejat. Obre la configuració per activar-lo.',
          deniedForever: true,
        );
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 8),
      );
      return (
        focus: LatLng(position.latitude, position.longitude),
        mode: _LocationMode.user,
        banner: null,
        deniedForever: false,
      );
    } catch (_) {
      return (
        focus: _barcelona,
        mode: _LocationMode.fallbackBarcelona,
        banner: 'No s\'ha pogut obtenir el GPS.',
        deniedForever: false,
      );
    }
  }

  Future<void> _moveCameraToFocus() async {
    final controller = mapController;
    if (controller == null) return;
    _lastCamera = CameraPosition(target: _focus, zoom: _initialZoom);
    try {
      await controller.animateCamera(
        CameraUpdate.newLatLngZoom(_focus, _initialZoom),
      );
    } catch (_) {
      // El mapa pot no estar llest encara.
    }
  }

  Future<void> _offerOpenSettings() async {
    if (!mounted) return;
    final open = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Permís d\'ubicació'),
        content: const Text(
          'Has bloquejat l\'accés a la ubicació. Sense aquest permís no podem centrar el mapa a la teva posició.\n\nVols obrir la configuració de l\'app per activar-lo?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Ara no'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: CaliuColors.maroon),
            child: const Text('Obrir configuració'),
          ),
        ],
      ),
    );
    if (open == true) {
      await Geolocator.openAppSettings();
    }
  }

  Future<void> _onRecenterPressed() async {
    if (_locating) return;
    await _resolveAndApplyFocus(requestIfNeeded: true);
    if (!mounted) return;
    // Diàleg de configuració només si l'usuari ho demana i el permís està bloquejat.
    if (_permissionDeniedForever) {
      await _offerOpenSettings();
    }
    if (!mounted) return;
    _loadedBounds = null;
    _loadedZoom = null;
    _confirmedEmptyBounds = null;
    await _loadAroundFocus(focus: _focus, notifyIfEmpty: false);
  }

  LatLngBounds _expandBounds(LatLngBounds bounds, double marginFraction) {
    final latSpan = (bounds.northeast.latitude - bounds.southwest.latitude)
        .abs();
    final lngSpan = (bounds.northeast.longitude - bounds.southwest.longitude)
        .abs();
    final latPad = latSpan * marginFraction;
    final lngPad = lngSpan * marginFraction;
    return LatLngBounds(
      southwest: LatLng(
        bounds.southwest.latitude - latPad,
        bounds.southwest.longitude - lngPad,
      ),
      northeast: LatLng(
        bounds.northeast.latitude + latPad,
        bounds.northeast.longitude + lngPad,
      ),
    );
  }

  bool _boundsContain(LatLngBounds outer, LatLngBounds inner) {
    return outer.southwest.latitude <= inner.southwest.latitude &&
        outer.southwest.longitude <= inner.southwest.longitude &&
        outer.northeast.latitude >= inner.northeast.latitude &&
        outer.northeast.longitude >= inner.northeast.longitude;
  }

  bool _isUsableBounds(LatLngBounds bounds) {
    final latSpan = (bounds.northeast.latitude - bounds.southwest.latitude)
        .abs();
    final lngSpan = (bounds.northeast.longitude - bounds.southwest.longitude)
        .abs();
    return latSpan > 0.002 && lngSpan > 0.002 && latSpan < 40 && lngSpan < 40;
  }

  LatLng _boundsCenter(LatLngBounds bounds) {
    return LatLng(
      (bounds.southwest.latitude + bounds.northeast.latitude) / 2,
      (bounds.southwest.longitude + bounds.northeast.longitude) / 2,
    );
  }

  double _radiusKmForBounds(LatLngBounds bounds) {
    final meters = Geolocator.distanceBetween(
      bounds.southwest.latitude,
      bounds.southwest.longitude,
      bounds.northeast.latitude,
      bounds.northeast.longitude,
    );
    return (meters / 2000).clamp(3.0, 60.0);
  }

  LatLngBounds _boundsAround(LatLng center, double radiusKm) {
    final latDelta = radiusKm / 111.0;
    final lngDelta = radiusKm / 85.0;
    return LatLngBounds(
      southwest: LatLng(
        center.latitude - latDelta,
        center.longitude - lngDelta,
      ),
      northeast: LatLng(
        center.latitude + latDelta,
        center.longitude + lngDelta,
      ),
    );
  }

  Future<void> _reloadForVisibleRegion({
    bool force = false,
    bool notifyIfEmpty = false,
    bool notifyErrors = false,
  }) async {
    if (!mounted) return;

    LatLngBounds visible;
    final controller = mapController;
    if (controller != null) {
      try {
        visible = await controller.getVisibleRegion();
        if (!_isUsableBounds(visible)) {
          visible = _boundsAround(_lastCamera?.target ?? _focus, 8);
        }
      } catch (_) {
        visible = _boundsAround(_lastCamera?.target ?? _focus, 8);
      }
    } else {
      visible = _boundsAround(_lastCamera?.target ?? _focus, 8);
    }

    final zoom = _lastCamera?.zoom ?? _initialZoom;
    // Allunyar: la finestra creix; el marge carregat pot continuar “contenint”
    // la vista i cal forçar fetch (si no, zones noves sense pins).
    final zoomedOutSinceLoad =
        _loadedZoom != null && zoom < (_loadedZoom! - 0.6);

    final alreadyConfirmedEmpty =
        _confirmedEmptyBounds != null &&
        _boundsContain(_confirmedEmptyBounds!, visible);

    if (!force) {
      // Zona ja sabuda buida → no insistir (el refresh manual sí que força).
      if (alreadyConfirmedEmpty) return;
      if (_eventsRequestInFlight) return;
      if (!zoomedOutSinceLoad &&
          _loadedBounds != null &&
          _boundsContain(_loadedBounds!, visible)) {
        return;
      }
    }

    final queryBounds = _expandBounds(visible, _viewportMargin);
    final center = _boundsCenter(queryBounds);
    final radiusKm = _radiusKmForBounds(queryBounds);

    await _loadEventMarkers(
      lat: center.latitude,
      lng: center.longitude,
      radiusKm: radiusKm,
      queryBounds: queryBounds,
      notifyIfEmpty: notifyIfEmpty,
      notifyErrors: notifyErrors,
    );
  }

  Future<void> _loadAroundFocus({
    required LatLng focus,
    bool notifyIfEmpty = false,
  }) async {
    const radiusKm = 12.0;
    final queryBounds = _expandBounds(
      _boundsAround(focus, radiusKm / (1 + _viewportMargin)),
      _viewportMargin,
    );
    await _loadEventMarkers(
      lat: focus.latitude,
      lng: focus.longitude,
      radiusKm: radiusKm,
      queryBounds: queryBounds,
      notifyIfEmpty: notifyIfEmpty,
      notifyErrors: notifyIfEmpty,
    );
  }

  Future<void> _loadEventMarkers({
    required double lat,
    required double lng,
    required double radiusKm,
    required LatLngBounds queryBounds,
    bool notifyIfEmpty = false,
    bool notifyErrors = true,
  }) async {
    if (!mounted || _radius.locating) return;
    final selectedCenter = _radius.center;
    if (selectedCenter != null && _radius.radiusKm != null) {
      lat = selectedCenter.latitude;
      lng = selectedCenter.longitude;
      radiusKm = _radius.radiusKm!;
    }
    final generation = ++_loadGeneration;
    _eventsRequestInFlight = true;

    try {
      final events = await _eventsApi.fetchNearby(
        lat: lat,
        lng: lng,
        radiusKm: radiusKm,
        limit: 250,
      );
      if (!mounted || generation != _loadGeneration) return;

      final withLocation = events.where((e) => e.hasLocation).toList();
      final byId = indexEventsWithLocation(withLocation);
      _eventsById
        ..clear()
        ..addAll(byId);
      _loadedBounds = queryBounds;
      _loadedZoom = _lastCamera?.zoom ?? _initialZoom;
      // Si no hi ha res: marcar la zona perquè no tornem a demanar en bucle.
      _confirmedEmptyBounds = withLocation.isEmpty ? queryBounds : null;

      setState(() {
        _clusteringEnabled = shouldClusterAtZoom(
          _lastCamera?.zoom ?? _initialZoom,
        );
        // No recrear el ClusterManager a cada fetch: és lent i fa parpellejar.
        _applyMarkersFromEvents(
          withLocation,
          recreateClusterManager:
              _clusteringEnabled && _clusterManagers.isEmpty,
        );
        _selected = selectionAfterReload(_selected, _eventsById);
        _eventsRequestInFlight = false;
      });

      if (notifyIfEmpty && withLocation.isEmpty) {
        _showMessage('Cap esdeveniment amb ubicació en aquest radi.');
      }
    } on EventsApiException catch (e) {
      if (!mounted || generation != _loadGeneration) return;
      _eventsRequestInFlight = false;
      if (notifyErrors) _showMessage(e.message);
    } catch (_) {
      if (!mounted || generation != _loadGeneration) return;
      _eventsRequestInFlight = false;
      if (notifyErrors) {
        _showMessage('No s\'han pogut carregar els esdeveniments.');
      }
    }
  }

  /// Actualitza `_markers` / `_clusterManagers` a partir dels events en memòria.
  ///
  /// [recreateClusterManager]: true en càrregues noves o en tornar al mode
  /// clúster (evita clústers fantasma); false si només canvien els pins.
  void _applyMarkersFromEvents(
    Iterable<Event> events, {
    required bool recreateClusterManager,
  }) {
    if (_clusteringEnabled &&
        (recreateClusterManager || _clusterManagers.isEmpty)) {
      _clusterGeneration++;
    }
    final markerSet = buildEventMarkerSet(
      events,
      clusterGeneration: _clusterGeneration,
      cluster: _clusteringEnabled,
      onTap: _selectEvent,
      onInfoWindowTap: _openInGoogleMaps,
      onClusterTap: _onClusterTap,
    );
    _clusterManagers = markerSet.clusterManagers;
    _markers = markerSet.markers;
  }

  /// #115: en tocar un clúster, apropa la càmera (bounds o zoom si coincideixen).
  Future<void> _onClusterTap(Cluster cluster) async {
    if (_clusterZoomInFlight) return;
    final controller = mapController;
    if (controller == null) return;

    final focus = focusForClusterTap(
      bounds: cluster.bounds,
      position: cluster.position,
      currentZoom: _lastCamera?.zoom ?? _initialZoom,
      maxZoom: kMapMaxZoom,
    );

    final CameraUpdate? update = switch (focus) {
      ClusterTapFitBounds(:final bounds, :final paddingPx) =>
        CameraUpdate.newLatLngBounds(bounds, paddingPx),
      ClusterTapZoomTo(:final center, :final zoom) =>
        CameraUpdate.newLatLngZoom(center, zoom),
      ClusterTapNoop() => null,
    };
    if (update == null) return;

    _clusterZoomInFlight = true;
    try {
      await controller.animateCamera(update);
    } catch (_) {
      // Mapa no llest o bounds invàlids.
    } finally {
      _clusterZoomInFlight = false;
    }
  }

  void _syncClusteringWithZoom(double zoom) {
    final shouldCluster = shouldClusterAtZoom(zoom);
    if (shouldCluster == _clusteringEnabled) return;
    if (!mounted) return;
    final enablingClusters = shouldCluster;
    setState(() {
      _clusteringEnabled = shouldCluster;
      // Pins de cache de seguida (sense esperar la xarxa).
      _applyMarkersFromEvents(
        _eventsById.values,
        recreateClusterManager: enablingClusters,
      );
    });
    if (enablingClusters) {
      // Allunyar: pins de cache ja visibles; a l'idle força fetch de la zona ampla.
      _pendingWideReload = true;
      _loadedZoom = null;
      _loadedBounds = null;
      _confirmedEmptyBounds = null;
    }
  }

  void _selectEvent(Event event) {
    setState(() => _selected = _eventsById[event.id] ?? event);
  }

  void _clearSelection() {
    if (_selected == null) return;
    setState(() => _selected = null);
  }

  void _openDetail(Event event) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EventDetailScreen(
          eventId: event.id,
          initialEvent: _eventsById[event.id] ?? event,
        ),
      ),
    );
  }

  Future<void> _openInGoogleMaps(Event event) async {
    final uri = event.googleMapsUri;
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) _showMessage('No s\'ha pogut obrir Google Maps');
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _refresh() async {
    _confirmedEmptyBounds = null;
    await _reloadForVisibleRegion(
      force: true,
      notifyIfEmpty: true,
      notifyErrors: true,
    );
  }

  void _onCameraMove(CameraPosition position) {
    _lastCamera = position;
    // Dissolve / agrupa segons el zoom (el ClusterManager natiu no té maxZoom).
    _syncClusteringWithZoom(position.zoom);
  }

  void _onCameraIdle() {
    if (!_acceptCameraIdleReloads) return;
    _cameraIdleTimer?.cancel();
    _cameraIdleTimer = Timer(const Duration(milliseconds: 180), () {
      final force = _pendingWideReload;
      _pendingWideReload = false;
      unawaited(
        _reloadForVisibleRegion(
          force: force,
          notifyIfEmpty: false,
          notifyErrors: false,
        ),
      );
    });
  }

  Future<void> _onMapCreated(GoogleMapController controller) async {
    mapController = controller;
    _lastCamera = CameraPosition(target: _focus, zoom: _initialZoom);
    await _moveCameraToFocus();
    await _loadAroundFocus(focus: _focus, notifyIfEmpty: false);

    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;
    await _reloadForVisibleRegion(force: true, notifyIfEmpty: true);
    if (!mounted) return;
    _acceptCameraIdleReloads = true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: CaliuColors.maroonDeep,
        foregroundColor: Colors.white,
        title: const Text('Mapa'),
        actions: [
          IconButton(
            tooltip: _hasUserLocation
                ? 'Centrar a la meva ubicació'
                : 'Activar ubicació',
            onPressed: _locating ? null : _onRecenterPressed,
            icon: _locating
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Icon(
                    _hasUserLocation
                        ? Icons.my_location
                        : Icons.location_disabled,
                  ),
          ),
          IconButton(
            tooltip: 'Cerca',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      SearchScreen(radius: _radius, api: _eventsApi),
                ),
              );
            },
            icon: const Icon(Icons.search),
          ),
          IconButton(
            tooltip: 'Actualitzar',
            onPressed: _eventsRequestInFlight ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: !_mapReadyToShow
          ? const ColoredBox(color: CaliuColors.beige)
          : Column(
              children: [
                if (_locationBanner != null)
                  Material(
                    color: CaliuColors.beigeCard,
                    child: ListTile(
                      dense: true,
                      leading: Icon(
                        _permissionDeniedForever
                            ? Icons.location_off
                            : Icons.location_city,
                        color: CaliuColors.maroon,
                      ),
                      title: Text(
                        _locationBanner!,
                        style: const TextStyle(fontSize: 13),
                      ),
                      trailing: _permissionDeniedForever
                          ? TextButton(
                              onPressed: () => Geolocator.openAppSettings(),
                              child: const Text('Configuració'),
                            )
                          : TextButton(
                              onPressed: _locating ? null : _onRecenterPressed,
                              child: const Text('Reintentar'),
                            ),
                    ),
                  ),
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: GoogleMap(
                          onMapCreated: _onMapCreated,
                          style: _mapStyleNoPois,
                          initialCameraPosition: CameraPosition(
                            target: _focus,
                            zoom: _initialZoom,
                          ),
                          // #117: càmera limitada a Catalunya.
                          cameraTargetBounds: CameraTargetBounds(
                            _cataloniaBounds,
                          ),
                          minMaxZoomPreference: const MinMaxZoomPreference(
                            7,
                            kMapMaxZoom,
                          ),
                          // #153: només si tenim permís (evita comportaments estranys).
                          myLocationEnabled: _hasUserLocation,
                          myLocationButtonEnabled: false,
                          mapToolbarEnabled: false,
                          compassEnabled: true,
                          // #114/#115: clustering natiu + zoom en tocar el clúster.
                          clusterManagers: _clusterManagers,
                          markers: _markers,
                          onCameraMove: _onCameraMove,
                          onCameraIdle: _onCameraIdle,
                          // #44: tocar el mapa fora d'un marcador tanca la previsualització.
                          onTap: (_) => _clearSelection(),
                        ),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: MapEventPreview(
                          selected: _selected,
                          active: widget.isActive,
                          onOpen: _openDetail,
                          onClose: _clearSelection,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
