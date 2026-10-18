import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'config.dart';
import 'data/event.dart';
import 'data/events_api.dart';
import 'event_detail_screen.dart';

class MapView extends StatefulWidget {
  const MapView({super.key});

  @override
  State<MapView> createState() => _MapViewState();
}

class _MapViewState extends State<MapView> {
  final EventsApi _eventsApi = EventsApi();

  GoogleMapController? mapController;
  Position? currentPosition;
  Set<Marker> _markers = {};
  final Map<String, Event> _eventsById = {};

  bool isLoadingLocation = true;
  bool isLoadingEvents = false;

  final LatLng defaultLocation = const LatLng(41.3851, 2.1734);

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _determinePosition();
    final lat = currentPosition?.latitude ?? defaultLocation.latitude;
    final lng = currentPosition?.longitude ?? defaultLocation.longitude;
    await _loadEventMarkers(lat: lat, lng: lng);
  }

  Future<void> _determinePosition() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          setState(() => isLoadingLocation = false);
          _showMessage('Serveis d\'ubicació desactivats. Usem Barcelona.');
        }
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            setState(() => isLoadingLocation = false);
            _showMessage('Permís d\'ubicació denegat. Usem Barcelona.');
          }
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() => isLoadingLocation = false);
          _showMessage('Permís d\'ubicació bloquejat. Usem Barcelona.');
        }
        return;
      }

      final position = await Geolocator.getCurrentPosition();
      if (!mounted) return;

      setState(() {
        currentPosition = position;
        isLoadingLocation = false;
      });

      await mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(position.latitude, position.longitude),
          14,
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => isLoadingLocation = false);
        _showMessage('No s\'ha pogut obtenir el GPS. Usem Barcelona.');
      }
    }
  }

  Future<void> _loadEventMarkers({
    required double lat,
    required double lng,
  }) async {
    if (!mounted) return;
    setState(() => isLoadingEvents = true);

    try {
      final events = await _eventsApi.fetchNearby(
        lat: lat,
        lng: lng,
        radiusKm: 15,
        limit: 50,
      );
      if (!mounted) return;

      final withLocation = events.where((e) => e.hasLocation).toList();
      _eventsById
        ..clear()
        ..addEntries(withLocation.map((e) => MapEntry(e.id, e)));

      setState(() {
        _markers = withLocation.map(_markerFor).toSet();
        isLoadingEvents = false;
      });

      if (withLocation.isEmpty) {
        _showMessage('Cap esdeveniment amb ubicació en aquest radi.');
      }
    } on EventsApiException catch (e) {
      if (!mounted) return;
      setState(() => isLoadingEvents = false);
      _showMessage(e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => isLoadingEvents = false);
      _showMessage('Error carregant esdeveniments: $e');
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
    final lat = currentPosition?.latitude ?? defaultLocation.latitude;
    final lng = currentPosition?.longitude ?? defaultLocation.longitude;
    await _loadEventMarkers(lat: lat, lng: lng);
  }

  @override
  Widget build(BuildContext context) {
    final showLoading = isLoadingLocation || isLoadingEvents;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Explorar Esdeveniments (Caliu)'),
        actions: [
          IconButton(
            tooltip: 'Tornar a carregar events',
            onPressed: isLoadingEvents ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Stack(
        children: [
          GoogleMap(
            onMapCreated: (GoogleMapController controller) {
              mapController = controller;
            },
            initialCameraPosition: CameraPosition(
              target: currentPosition != null
                  ? LatLng(
                      currentPosition!.latitude,
                      currentPosition!.longitude,
                    )
                  : defaultLocation,
              zoom: 12,
            ),
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
            markers: _markers,
          ),
          if (showLoading)
            const Center(
              child: Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(width: 16),
                      Text('Carregant…'),
                    ],
                  ),
                ),
              ),
            ),
          Positioned(
            left: 12,
            bottom: 24,
            child: Card(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Text(
                  '${_markers.length} pins · $apiBaseUrl',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
