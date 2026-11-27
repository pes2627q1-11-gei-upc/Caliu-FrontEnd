import 'dart:async';

import 'package:flutter/foundation.dart';

import 'auth_session.dart';
import 'event.dart';
import 'favorites_api.dart';

/// Estat compartit dels preferits perquè el cor de la fitxa, el de les
/// targetes de la llista i la pantalla de Preferits estiguin sempre
/// sincronitzats (H.U #16).
///
/// Els canvis són optimistes: el cor canvia a l'instant i, si la petició
/// falla, es desfà el canvi i es rellança l'error perquè la UI l'expliqui.
class FavoritesController extends ChangeNotifier {
  FavoritesController(this._api, {this.session});

  /// Instància de l'app. Els tests n'injecten una de pròpia.
  static final FavoritesController shared = () {
    final session = AuthSession();
    return FavoritesController(
      createFavoritesApi(session: session),
      session: session,
    );
  }();

  final FavoritesApi _api;

  /// Si és null, es considera que sempre hi ha sessió (tests).
  final AuthSessionStore? session;

  /// Ordre d'inserció: l'últim és el preferit més recent.
  final Map<String, Event> _events = {};

  /// Peticions en curs: es completen (sense error) quan acaben.
  final Map<String, Future<void>> _inFlight = {};
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
  bool isPending(String eventId) => _inFlight.containsKey(eventId);

  /// Espera que acabi la petició en curs per a aquest esdeveniment, si n'hi
  /// ha (p. ex. "Desfer" just després de treure'l, tasca #167).
  Future<void> settled(String eventId) =>
      _inFlight[eventId] ?? Future<void>.value();

  /// Hi ha un token desat? Si no, cal demanar login abans de marcar (#191).
  Future<bool> hasSession() async {
    final session = this.session;
    if (session == null) return true;
    try {
      final token = await session.readToken();
      return token != null && token.isNotEmpty;
    } on Exception {
      return false;
    }
  }

  /// Oblida els preferits locals (en tancar o caducar la sessió).
  void clear() {
    _events.clear();
    _inFlight.clear();
    _loaded = false;
    _error = null;
    notifyListeners();
  }

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
    if (_inFlight.containsKey(id)) return wasFavorite;
    final done = Completer<void>();
    _inFlight[id] = done.future;

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
      if (identical(_inFlight[id], done.future)) _inFlight.remove(id);
      done.complete();
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
