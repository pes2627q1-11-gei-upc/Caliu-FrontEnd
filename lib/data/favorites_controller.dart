import 'package:flutter/foundation.dart';

import 'event.dart';
import 'favorites_api.dart';

/// Estat compartit dels preferits perquè el cor de la fitxa, el de les
/// targetes de la llista i la pantalla de Preferits estiguin sempre
/// sincronitzats (H.U #16).
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

  /// Ordre d'inserció: l'últim és el preferit més recent.
  final Map<String, Event> _events = {};
  final Set<String> _pending = {};
  bool _loaded = false;
  bool _loading = false;
  FavoritesApiException? _error;

  bool get isLoaded => _loaded;

  bool get isLoading => _loading;

  /// Error de l'última càrrega (null si ha anat bé).
  FavoritesApiException? get error => _error;

  /// Preferits, el més recent primer.
  List<Event> get favorites =>
      List.unmodifiable(_events.values.toList().reversed);

  bool isFavorite(String eventId) => _events.containsKey(eventId);

  /// Hi ha una petició en curs per a aquest esdeveniment.
  bool isPending(String eventId) => _pending.contains(eventId);

  /// Carrega els preferits del servidor. Si falla, la llista queda buida i
  /// l'error es guarda a [error] perquè la pantalla de Preferits l'expliqui.
  Future<void> load() async {
    _loading = true;
    notifyListeners();
    try {
      final favorites = await _api.fetchFavorites();
      _events
        ..clear()
        ..addEntries(favorites.reversed.map((e) => MapEntry(e.id, e)));
      _loaded = true;
      _error = null;
    } on FavoritesApiException catch (e) {
      _events.clear();
      _error = e;
    } catch (_) {
      _events.clear();
      _error = const FavoritesApiException(
        'No s\'han pogut carregar els preferits',
      );
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Afegeix o treu [event] dels preferits i retorna el nou estat.
  ///
  /// Mentre hi ha una petició en curs per al mateix esdeveniment, els tocs
  /// repetits s'ignoren i es retorna l'estat actual.
  Future<bool> toggle(Event event) async {
    final id = event.id;
    final wasFavorite = _events.containsKey(id);
    if (!_pending.add(id)) return wasFavorite;

    _setFavorite(event, !wasFavorite);
    try {
      if (wasFavorite) {
        await _api.removeFavorite(id);
      } else {
        await _api.addFavorite(event);
      }
      return !wasFavorite;
    } catch (_) {
      _setFavorite(event, wasFavorite);
      rethrow;
    } finally {
      _pending.remove(id);
      notifyListeners();
    }
  }

  void _setFavorite(Event event, bool favorite) {
    if (favorite) {
      _events[event.id] = event;
    } else {
      _events.remove(event.id);
    }
    notifyListeners();
  }
}
