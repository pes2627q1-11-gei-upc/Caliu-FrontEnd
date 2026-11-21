import 'package:flutter/foundation.dart';

import 'auth_api.dart';
import 'auth_session.dart';
import 'search_radius.dart';

/// Radi d'activitat desat a les preferències de l'usuari (H.U #9).
///
/// És el valor per defecte del mapa i de la cerca (tasca #125): es carrega en
/// obrir l'app i en iniciar sessió, s'actualitza en desar les preferències i
/// s'oblida en tancar la sessió.
class PreferredRadius extends ChangeNotifier {
  PreferredRadius({AuthApi? api, AuthSessionStore? session})
    : _api = api ?? AuthApi(),
      _session = session ?? AuthSession();

  /// Instància de l'app. Els tests n'injecten una de pròpia.
  static final PreferredRadius shared = PreferredRadius();

  final AuthApi _api;
  final AuthSessionStore _session;

  /// Radi en km, o null si no n'hi ha cap de desat (o no hi ha sessió).
  double? get km => _km;
  double? _km;

  int _generation = 0;

  /// Llegeix el radi de les preferències. Sense sessió o si falla, no n'hi ha.
  Future<void> load() async {
    final generation = ++_generation;
    double? km;
    try {
      final token = await _session.readToken();
      if (token != null && token.isNotEmpty) {
        km = (await _api.fetchUserPreferences(token)).proximitatKm;
      }
    } catch (_) {
      km = null;
    }
    if (generation != _generation) return;
    _set(km);
  }

  /// Nou valor desat des de la pantalla de preferències.
  void set(double? km) {
    ++_generation;
    _set(km);
  }

  /// En tancar o caducar la sessió.
  void clear() => set(null);

  void _set(double? km) {
    if (km == _km) return;
    _km = km;
    notifyListeners();
  }
}

/// Aplica el radi de les preferències com a valor per defecte de [radius]
/// (el filtre que comparteixen el mapa i la cerca, tasca #125).
///
/// Si l'usuari canvia o treu el radi a mà, no es trepitja fins que les
/// preferències tornin a canviar. Retorna la funció per deixar d'escoltar.
VoidCallback bindPreferredRadius(PreferredRadius preferred, SearchRadius radius) {
  double? applied;

  // El radi actual és el que es va posar per defecte (o encara s'està
  // obtenint la ubicació per posar-lo).
  bool isDefault() =>
      applied != null && (radius.locating || radius.radiusKm == applied);

  void update() {
    final km = preferred.km;
    final wasDefault = isDefault();
    if (km == null) {
      if (wasDefault) radius.clear();
      applied = null;
      return;
    }
    final untouched = radius.radiusKm == null && !radius.locating;
    if (!wasDefault && !untouched) return;
    final value = km.clamp(SearchRadius.minKm, SearchRadius.maxKm).toDouble();
    applied = value;
    radius.apply(value).ignore();
  }

  preferred.addListener(update);
  update();
  return () => preferred.removeListener(update);
}
