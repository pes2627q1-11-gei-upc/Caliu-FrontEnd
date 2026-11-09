import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'data/event.dart';
import 'data/events_api.dart';
import 'event_detail_screen.dart';
import 'search_screen.dart';
import 'theme/caliu_colors.dart';

/// Amaga POIs i etiquetes de llocs de Google (feedback demo: sense info externa).
const String _mapStyleNoPois = '''
[
  {"featureType":"poi","stylers":[{"visibility":"off"}]},
  {"featureType":"transit","stylers":[{"visibility":"off"}]}
]
''';

/// Marge fora de la finestra visible perquè els pins arribin abans de veure's.
const double _viewportMargin = 0.4;

class MapView extends StatefulWidget {
  const MapView({super.key});

  @override
  State<MapView> createState() => _MapViewState();
}

class _MapViewState extends State<MapView> {
  final EventsApi _eventsApi = EventsApi();

  GoogleMapController? mapController;
  Set<Marker> _markers = {};
  final Map<String, Event> _eventsById = {};

  bool _eventsRequestInFlight = false;
  bool _mapReadyToShow = false;
  bool _acceptCameraIdleReloads = false;

  LatLng _focus = const LatLng(41.3851, 2.1734);
  static const double _initialZoom = 14;

  CameraPosition? _lastCamera;
  LatLngBounds? _loadedBounds;
  Timer? _cameraIdleTimer;
  int _loadGeneration = 0;

  @override
  void dispose() {
    _cameraIdleTimer?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrap());
  }

  Future<void> _bootstrap() async {
    _focus = await _resolveFocus();
    if (!mounted) return;
    // Mostrem el mapa ja centrat al focus (GPS o Barcelona).
    setState(() => _mapReadyToShow = true);
  }

  Future<LatLng> _resolveFocus() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showMessage('Serveis d\'ubicació desactivats. Usem Barcelona.');
        return _focus;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _showMessage('Permís d\'ubicació denegat. Usem Barcelona.');
          return _focus;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        _showMessage('Permís d\'ubicació bloquejat. Usem Barcelona.');
        return _focus;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 8),
      );
      return LatLng(position.latitude, position.longitude);
    } catch (_) {
      if (mounted) {
        _showMessage('No s\'ha pogut obtenir el GPS. Usem Barcelona.');
      }
      return _focus;
    }
  }

  LatLngBounds _expandBounds(LatLngBounds bounds, double marginFraction) {
    final latSpan =
        (bounds.northeast.latitude - bounds.southwest.latitude).abs();
    final lngSpan =
        (bounds.northeast.longitude - bounds.southwest.longitude).abs();
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
    final latSpan =
        (bounds.northeast.latitude - bounds.southwest.latitude).abs();
    final lngSpan =
        (bounds.northeast.longitude - bounds.southwest.longitude).abs();
    return latSpan > 0.002 &&
        lngSpan > 0.002 &&
        latSpan < 40 &&
        lngSpan < 40;
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
    // ~111 km per grau de latitud; lng aproximat a Catalunya.
    final latDelta = radiusKm / 111.0;
    final lngDelta = radiusKm / 85.0;
    return LatLngBounds(
      southwest: LatLng(center.latitude - latDelta, center.longitude - lngDelta),
      northeast: LatLng(center.latitude + latDelta, center.longitude + lngDelta),
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
          visible = _boundsAround(
            _lastCamera?.target ?? _focus,
            8,
          );
        }
      } catch (_) {
        visible = _boundsAround(_lastCamera?.target ?? _focus, 8);
      }
    } else {
      visible = _boundsAround(_lastCamera?.target ?? _focus, 8);
    }

    if (!force &&
        _loadedBounds != null &&
        _boundsContain(_loadedBounds!, visible)) {
      return;
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
    // Radi inicial coherent amb zoom 14 + marge (abans que getVisibleRegion sigui fiable).
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
    if (!mounted) return;
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
      _eventsById
        ..clear()
        ..addEntries(withLocation.map((e) => MapEntry(e.id, e)));
      _loadedBounds = queryBounds;

      setState(() {
        _markers = withLocation.map(_markerFor).toSet();
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

  Marker _markerFor(Event event) {
    final category =
        event.categories.isNotEmpty ? event.categories.first : null;
    final distanceKm = event.distanceMeters != null
        ? '${(event.distanceMeters! / 1000).toStringAsFixed(1)} km'
        : null;
    final snippet = [
      ?category,
      ?distanceKm,
    ].join(' · ');

    return Marker(
      markerId: MarkerId(event.id),
      position: event.location!,
      infoWindow: InfoWindow(
        title: event.title,
        snippet: snippet.isEmpty ? null : snippet,
      ),
      onTap: () => _openDetail(event),
    );
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

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _refresh() async {
    await _reloadForVisibleRegion(
      force: true,
      notifyIfEmpty: true,
      notifyErrors: true,
    );
  }

  void _onCameraMove(CameraPosition position) {
    _lastCamera = position;
  }

  void _onCameraIdle() {
    if (!_acceptCameraIdleReloads) return;
    _cameraIdleTimer?.cancel();
    _cameraIdleTimer = Timer(const Duration(milliseconds: 350), () {
      unawaited(
        _reloadForVisibleRegion(
          force: false,
          notifyIfEmpty: false,
          notifyErrors: false,
        ),
      );
    });
  }

  Future<void> _onMapCreated(GoogleMapController controller) async {
    mapController = controller;
    _lastCamera = CameraPosition(target: _focus, zoom: _initialZoom);

    // Carrega pins del focus actual (on està la càmera inicial).
    await _loadAroundFocus(focus: _focus, notifyIfEmpty: false);

    // Un fotograma perquè el mapa estabilitzí els bounds, després acceptem pan.
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
            tooltip: 'Cerca',
            onPressed: () {
              final target = _lastCamera?.target ?? _focus;
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SearchScreen(
                    lat: target.latitude,
                    lng: target.longitude,
                  ),
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
          : GoogleMap(
              onMapCreated: _onMapCreated,
              style: _mapStyleNoPois,
              initialCameraPosition: CameraPosition(
                target: _focus,
                zoom: _initialZoom,
              ),
              myLocationEnabled: true,
              myLocationButtonEnabled: true,
              mapToolbarEnabled: false,
              compassEnabled: true,
              markers: _markers,
              onCameraMove: _onCameraMove,
              onCameraIdle: _onCameraIdle,
              onTap: (_) {},
            ),
    );
  }
}
