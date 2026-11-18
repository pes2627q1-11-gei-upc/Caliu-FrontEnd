import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'auth_session.dart';
import 'event.dart';

class FavoritesApiException implements Exception {
  const FavoritesApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  /// L'usuari no té sessió: la UI ha de demanar login (tasca #191).
  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() => message;
}

/// Preferits de l'usuari autenticat (H.U #16).
///
/// El backend encara no exposa aquests endpoints. Proposta de contracte
/// (pendent de confirmar a l'OpenAPI del backend):
/// - `GET    /users/me/favorites`          → `{ "items": [Event, ...] }`
/// - `POST   /users/me/favorites`          → body `{ "eventId": "..." }`
/// - `DELETE /users/me/favorites/{eventId}`
abstract interface class FavoritesApi {
  /// Preferits de l'usuari, el més recent primer.
  Future<List<Event>> fetchFavorites();

  /// Afegeix [event] als preferits. Si ja hi és, no fa res.
  Future<void> addFavorite(Event event);

  /// Treu l'esdeveniment dels preferits. Si no hi és, no fa res.
  Future<void> removeFavorite(String eventId);

  Future<bool> isFavorite(String eventId);
}

/// Instància que fa servir l'app. Quan el backend estigui llest, aquí es
/// canviarà la implementació simulada per la HTTP sense tocar les pantalles.
FavoritesApi createFavoritesApi({AuthSessionStore? session}) =>
    MockFavoritesApi(session: session ?? AuthSession());

/// Implementació en memòria amb dades simulades mentre no hi ha backend.
class MockFavoritesApi implements FavoritesApi {
  MockFavoritesApi({
    this.session,
    List<Event>? seed,
    this.latency = const Duration(milliseconds: 300),
  }) {
    for (final event in (seed ?? sampleFavorites).reversed) {
      _favorites[event.id] = event;
    }
  }

  /// Si és null no es comprova la sessió.
  final AuthSessionStore? session;

  /// Retard artificial per simular la xarxa (zero als tests).
  final Duration latency;

  /// Ordre d'inserció: l'últim afegit és el més recent.
  final Map<String, Event> _favorites = {};

  @override
  Future<List<Event>> fetchFavorites() async {
    await _simulateRequest();
    return _favorites.values.toList().reversed.toList(growable: false);
  }

  @override
  Future<void> addFavorite(Event event) async {
    await _simulateRequest();
    if (event.id.isEmpty) {
      throw const FavoritesApiException(
        'Esdeveniment sense identificador',
        statusCode: 400,
      );
    }
    _favorites.putIfAbsent(event.id, () => event);
  }

  @override
  Future<void> removeFavorite(String eventId) async {
    await _simulateRequest();
    _favorites.remove(eventId);
  }

  @override
  Future<bool> isFavorite(String eventId) async {
    await _simulateRequest();
    return _favorites.containsKey(eventId);
  }

  Future<void> _simulateRequest() async {
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    final session = this.session;
    if (session == null) return;
    final token = await session.readToken();
    if (token == null || token.isEmpty) {
      throw const FavoritesApiException(
        'Cal iniciar sessió per gestionar els preferits',
        statusCode: 401,
      );
    }
  }
}

/// Preferits inicials simulats, perquè la pestanya no surti buida.
final List<Event> sampleFavorites = [
  Event(
    id: 'mock-fav-1',
    title: 'Exposició: Modernisme a Barcelona',
    description: 'Recorregut per obres i objectes del modernisme català.',
    startDate: DateTime(2026, 11, 1),
    endDate: DateTime(2027, 2, 28),
    venue: 'Museu Nacional d\'Art de Catalunya',
    municipality: 'Barcelona',
    comarca: 'Barcelonès',
    location: const LatLng(41.3685, 2.1534),
    categories: const ['exposicions'],
    price: 12,
  ),
  Event(
    id: 'mock-fav-2',
    title: 'Fira de Santa Llúcia',
    description: 'Fira tradicional de Nadal amb parades d\'artesania.',
    startDate: DateTime(2026, 11, 27),
    endDate: DateTime(2026, 12, 23),
    venue: 'Pla de la Seu',
    municipality: 'Barcelona',
    comarca: 'Barcelonès',
    location: const LatLng(41.3840, 2.1762),
    categories: const ['fires'],
    price: 0,
  ),
  Event(
    id: 'mock-fav-3',
    title: 'Fira de l\'Oli de Les Borges Blanques',
    startDate: DateTime(2027, 1, 15),
    endDate: DateTime(2027, 1, 17),
    municipality: 'Les Borges Blanques',
    comarca: 'Garrigues',
    location: const LatLng(41.5225, 0.8689),
    categories: const ['fires'],
  ),
];
