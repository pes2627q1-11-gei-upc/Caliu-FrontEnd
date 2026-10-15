import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

class MapView extends StatefulWidget {
  const MapView({super.key});

  @override
  State<MapView> createState() => _MapViewState();
}

class _MapViewState extends State<MapView> {
  GoogleMapController? mapController;
  Position? currentPosition;
  bool isLoadingLocation = true;

  // Coordenadas por defecto (Ej: Plaça Catalunya, Barcelona)
  // por si tarda en cargar el GPS
  final LatLng defaultLocation = const LatLng(41.3851, 2.1734);

  @override
  void initState() {
    super.initState();
    _determinePosition(); // Llamamos al GPS al iniciar la pantalla
  }

  /// Función para la Tarea #79: Obtener la ubicación del dispositivo mediante GPS
  Future<void> _determinePosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    // 1. Comprobar si el servicio de ubicación está habilitado
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() => isLoadingLocation = false);
      return Future.error('Los servicios de ubicación están deshabilitados.');
    }

    // 2. Comprobar permisos
    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        setState(() => isLoadingLocation = false);
        return Future.error('Los permisos de ubicación fueron denegados.');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      setState(() => isLoadingLocation = false);
      return Future.error('Permisos denegados permanentemente.');
    }

    // 3. Obtener la posición actual
    Position position = await Geolocator.getCurrentPosition();

    setState(() {
      currentPosition = position;
      isLoadingLocation = false;
    });

    // 4. Mover la cámara del mapa a la ubicación del usuario
    if (mapController != null) {
      mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(position.latitude, position.longitude),
          14.0, // Nivel de zoom
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Explorar Esdeveniments (Caliu)'),
      ),
      // Tarea #78: Integrar el paquete Google_maps_flutter
      body: Stack(
        children: [
          GoogleMap(
            onMapCreated: (GoogleMapController controller) {
              mapController = controller;
            },
            initialCameraPosition: CameraPosition(
              target: currentPosition != null
                  ? LatLng(currentPosition!.latitude, currentPosition!.longitude)
                  : defaultLocation,
              zoom: 12.0,
            ),
            // Activa el famoso "puntito azul" del GPS nativo de Google Maps
            myLocationEnabled: true,
            // Muestra el botón para centrar la cámara en el usuario
            myLocationButtonEnabled: true,
            // Aquí en el futuro cargarás los marcadores (Tarea #80)
            markers: {},
          ),

          // Mostrar un indicador de carga mientras busca el GPS
          if (isLoadingLocation)
            const Center(
              child: Card(
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(width: 16),
                      Text("Buscant ubicació..."),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}