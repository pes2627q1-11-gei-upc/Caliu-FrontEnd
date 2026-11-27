import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// Ubicació per ordenar les recomanacions per proximitat.
typedef RecommendationsLocation = ({double lat, double lng});

/// Ubicació actual per a les recomanacions, sense demanar permís (el mapa ja
/// ho fa). Primer l'última posició coneguda (no existeix a web) i, si no n'hi
/// ha, una de nova amb límit de temps. Null si no hi ha permís o servei.
///
/// La fan servir la pestanya «Per a tu» i la secció de recomanacions d'Inici.
Future<RecommendationsLocation?> recommendationsLocationIfAllowed() async {
  if (!await Geolocator.isLocationServiceEnabled()) return null;
  final permission = await Geolocator.checkPermission();
  if (permission != LocationPermission.always &&
      permission != LocationPermission.whileInUse) {
    return null;
  }
  final last = kIsWeb ? null : await Geolocator.getLastKnownPosition();
  final position =
      last ??
      await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 5),
      );
  return (lat: position.latitude, lng: position.longitude);
}
