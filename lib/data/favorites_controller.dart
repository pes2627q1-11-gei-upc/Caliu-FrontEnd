import 'package:flutter/foundation.dart';

import 'event.dart';
import 'favorites_api.dart';

/// Estat compartit dels preferits perquè el cor de la fitxa i el de les
/// targetes de la llista estiguin sempre sincronitzats (H.U #16).
///
/// Els canvis són optimistes: el cor canvia a l'instant i, si la petició
/// falla, es desfà el canvi i es rellança l'error perquè la UI l'expliqui.
class FavoritesController extends ChangeNotifier {
  FavoritesController(this._api);

  /// Instància de l'app. Els tests n'injecten una de pròpia.
  static final FavoritesController shared = FavoritesController(
    createFavoritesApi(),
  );

  final FavoritesApi _api;
  final Set<String> _ids = {};
  final Set<String> _pending = {};
  bool _loaded = false;

  bool get isLoaded => _loaded;

  bool isFavorite(String eventId) => _ids.contains(eventId);

  /// Hi ha una petició en curs per a aquest esdeveniment.
  bool isPending(String eventId) => _pending.contains(eventId);

  /// Carrega els preferits del servidor. Si l'usuari no té sessió o falla la
  /// xarxa, es queda amb la llista buida: no és un error per a la UI.
  Future<void> load() async {
    try {
      final favorites = await _api.fetchFavorites();
      _ids
        ..clear()
        ..addAll(favorites.map((e) => e.id));
      _loaded = true;
    } catch (_) {
      _ids.clear();
    }
    notifyListeners();
  }

  /// Afegeix o treu [event] dels preferits i retorna el nou estat.
  ///
  /// Mentre hi ha una petició en curs per al mateix esdeveniment, els tocs
  /// repetits s'ignoren i es retorna l'estat actual.
  Future<bool> toggle(Event event) async {
    final id = event.id;
    final wasFavorite = _ids.contains(id);
    if (!_pending.add(id)) return wasFavorite;

    _setFavorite(id, !wasFavorite);
    try {
      if (wasFavorite) {
        await _api.removeFavorite(id);
      } else {
        await _api.addFavorite(event);
      }
      return !wasFavorite;
    } catch (_) {
      _setFavorite(id, wasFavorite);
      rethrow;
    } finally {
      _pending.remove(id);
      notifyListeners();
    }
  }

  void _setFavorite(String id, bool favorite) {
    if (favorite) {
      _ids.add(id);
    } else {
      _ids.remove(id);
    }
    notifyListeners();
  }
}
