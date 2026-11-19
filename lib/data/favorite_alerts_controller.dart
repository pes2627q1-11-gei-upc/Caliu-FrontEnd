import 'package:flutter/foundation.dart';

import 'favorite_alerts_api.dart';

/// Estat compartit de les alertes dels preferits, perquè la campana de la
/// fitxa i la de la pestanya Guardats estiguin sincronitzades (H.U #52).
///
/// Els canvis són optimistes: la campana canvia a l'instant i, si la petició
/// falla, es desfà el canvi i es rellança l'error perquè la UI l'expliqui.
class FavoriteAlertsController extends ChangeNotifier {
  FavoriteAlertsController(this._api);

  /// Instància de l'app. Els tests n'injecten una de pròpia.
  static final FavoriteAlertsController shared = FavoriteAlertsController(
    createFavoriteAlertsApi(),
  );

  final FavoriteAlertsApi _api;
  final Set<String> _muted = {};
  final Set<String> _pending = {};

  /// Per defecte, les alertes d'un preferit estan actives.
  bool alertsEnabled(String eventId) => !_muted.contains(eventId);

  /// Hi ha una petició en curs per a aquest esdeveniment.
  bool isPending(String eventId) => _pending.contains(eventId);

  /// Carrega quins preferits tenen les alertes silenciades. Si falla (p. ex.
  /// sense sessió), es considera que totes estan actives.
  Future<void> load() async {
    try {
      final muted = await _api.fetchMuted();
      _muted
        ..clear()
        ..addAll(muted);
    } catch (_) {
      _muted.clear();
    }
    notifyListeners();
  }

  /// Oblida l'estat local (en tancar o caducar la sessió).
  void clear() {
    _muted.clear();
    _pending.clear();
    notifyListeners();
  }

  /// Activa o silencia les alertes de l'esdeveniment i retorna el nou estat
  /// (`true` = actives). Els tocs repetits durant una petició s'ignoren.
  Future<bool> toggle(String eventId) async {
    final wasEnabled = alertsEnabled(eventId);
    if (!_pending.add(eventId)) return wasEnabled;

    _setEnabled(eventId, !wasEnabled);
    try {
      await _api.setAlertsEnabled(eventId, enabled: !wasEnabled);
      return !wasEnabled;
    } catch (_) {
      _setEnabled(eventId, wasEnabled);
      rethrow;
    } finally {
      _pending.remove(eventId);
      notifyListeners();
    }
  }

  void _setEnabled(String eventId, bool enabled) {
    if (enabled) {
      _muted.remove(eventId);
    } else {
      _muted.add(eventId);
    }
    notifyListeners();
  }
}
