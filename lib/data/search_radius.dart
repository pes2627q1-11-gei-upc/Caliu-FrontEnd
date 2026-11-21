import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'event_query.dart';

/// Estat compartit per la cerca i el mapa; no modifica les preferències.
class SearchRadius extends ChangeNotifier {
  SearchRadius({Future<LatLng> Function()? locate})
    : _locate = locate ?? _currentPosition;

  static const minKm = 0.1;
  static const maxKm = 500.0;
  static const unavailableMessage =
      'No podem aplicar el radi sense la teva ubicació. Activa-la i torna-ho a provar.';
  final Future<LatLng> Function() _locate;
  LatLng? center;
  double? radiusKm;

  /// Filtre de preu confirmat (#157): `free` | `paid` | null.
  String? price;
  bool locating = false;
  String? error;
  bool _disposed = false;
  int _generation = 0;

  /// Còpia d'edició: comparteix el proveïdor de GPS, però no notifica el mapa.
  SearchRadius fork() => SearchRadius(locate: _locate)
    ..center = center
    ..radiusKm = radiusKm
    ..price = price;

  void adopt(SearchRadius draft) {
    ++_generation;
    center = draft.center;
    radiusKm = draft.radiusKm;
    price = draft.price;
    locating = false;
    error = null;
    notifyListeners();
  }

  /// Actualitza el preu provisional (draft) o confirmat i notifica.
  void updatePrice(String? value) {
    assert(
      EventPriceFilter.isValid(value),
      'price ha de ser free, paid o null',
    );
    if (price == value) return;
    price = value;
    notifyListeners();
  }

  Future<void> apply(double km) async {
    if (!km.isFinite || km < minKm || km > maxKm) {
      throw ArgumentError.value(km, 'km');
    }
    final generation = ++_generation;
    if (center != null) {
      radiusKm = km;
      error = null;
      notifyListeners();
      return;
    }
    locating = true;
    radiusKm = null;
    center = null;
    error = null;
    notifyListeners();
    try {
      final position = await _locate();
      if (_disposed || generation != _generation) return;
      center = position;
      radiusKm = km;
    } catch (_) {
      if (_disposed || generation != _generation) return;
      error = unavailableMessage;
    }
    if (_disposed || generation != _generation) return;
    locating = false;
    notifyListeners();
  }

  void clear() {
    ++_generation;
    radiusKm = null;
    center = null;
    price = null;
    locating = false;
    error = null;
    notifyListeners();
  }

  static Future<LatLng> _currentPosition() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw StateError('Location disabled');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw StateError('Location denied');
    }
    final position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
      timeLimit: const Duration(seconds: 15),
    );
    return LatLng(position.latitude, position.longitude);
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    super.dispose();
  }
}
