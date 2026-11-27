import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';
import 'auth_session.dart';
import 'event.dart';
import 'favorite_alerts_api.dart';
import 'favorites_api.dart';

/// Client HTTP comú dels preferits i de les seves alertes (tasca #207).
///
/// Endpoints (OpenAPI del backend):
/// - `GET /users/me/favorites` → `{ "items": [Event + notificacionsActives] }`
/// - `POST /users/me/favorites` → `{ "eventId" }`, 204 (idempotent)
/// - `DELETE /users/me/favorites/{eventId}` → 204 (idempotent)
/// - `PATCH /users/me/favorites/{eventId}` → `{ "notificacionsActives" }`, 204
class FavoritesHttpClient {
  FavoritesHttpClient({
    http.Client? client,
    String? baseUrl,
    AuthSessionStore? session,
  }) : _client = client ?? http.Client(),
       _baseUrl = baseUrl ?? apiBaseUrl,
       _session = session ?? AuthSession();

  final http.Client _client;
  final String _baseUrl;
  final AuthSessionStore _session;

  static const _timeout = Duration(seconds: 15);

  /// Preferits del compte, amb l'estat de les alertes de cadascun.
  Future<List<(Event, bool)>> fetchFavorites() async {
    final response = await _send('GET', '/users/me/favorites');
    _requireStatus(response, 200, 'No s\'han pogut carregar els preferits');
    final dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw const FavoritesApiException(
        'El servidor ha retornat una resposta inesperada',
      );
    }
    final items = decoded is Map<String, dynamic> ? decoded['items'] : null;
    if (items is! List) {
      throw const FavoritesApiException(
        'La llista de preferits no té el format esperat',
      );
    }
    return [
      for (final item in items.whereType<Map<String, dynamic>>())
        (Event.fromJson(item), item['notificacionsActives'] != false),
    ];
  }

  Future<void> add(String eventId) async {
    final response = await _send(
      'POST',
      '/users/me/favorites',
      body: {'eventId': eventId},
    );
    _requireStatus(
      response,
      204,
      'No s\'ha pogut afegir als preferits',
      notFoundMessage: 'Aquest esdeveniment ja no existeix',
    );
  }

  Future<void> remove(String eventId) async {
    final response = await _send('DELETE', '/users/me/favorites/$eventId');
    _requireStatus(response, 204, 'No s\'ha pogut treure dels preferits');
  }

  Future<void> setAlertsEnabled(String eventId, {required bool enabled}) async {
    final response = await _send(
      'PATCH',
      '/users/me/favorites/$eventId',
      body: {'notificacionsActives': enabled},
    );
    _requireStatus(
      response,
      204,
      'No s\'han pogut actualitzar les alertes',
      notFoundMessage: 'Aquest esdeveniment ja no és als teus preferits',
    );
  }

  Future<http.Response> _send(
    String method,
    String path, {
    Object? body,
  }) async {
    final String? token;
    try {
      token = await _session.readToken();
    } on Exception {
      throw _unauthorized;
    }
    // Sense sessió no cal ni fer la petició: la UI demanarà login (#191).
    if (token == null || token.isEmpty) throw _unauthorized;

    final headers = <String, String>{
      'authorization': 'Bearer $token',
      if (body != null) 'content-type': 'application/json',
    };
    final uri = Uri.parse('$_baseUrl$path');
    final encoded = body == null ? null : jsonEncode(body);
    try {
      final request = switch (method) {
        'GET' => _client.get(uri, headers: headers),
        'POST' => _client.post(uri, headers: headers, body: encoded),
        'PATCH' => _client.patch(uri, headers: headers, body: encoded),
        'DELETE' => _client.delete(uri, headers: headers),
        _ => throw StateError('Mètode HTTP no admès: $method'),
      };
      return await request.timeout(_timeout);
    } on Exception {
      throw const FavoritesApiException(
        'No s\'ha pogut connectar amb el servidor. Comprova la connexió i '
        'torna-ho a provar.',
      );
    }
  }

  static const _unauthorized = FavoritesApiException(
    'Cal iniciar sessió per gestionar els preferits',
    statusCode: 401,
  );

  void _requireStatus(
    http.Response response,
    int expected,
    String fallback, {
    String? notFoundMessage,
  }) {
    final status = response.statusCode;
    if (status == expected) return;
    if (status == 401) throw _unauthorized;
    if (status == 404 && notFoundMessage != null) {
      throw FavoritesApiException(notFoundMessage, statusCode: 404);
    }
    throw FavoritesApiException(fallback, statusCode: status);
  }
}

/// Preferits contra el backend real (substitueix [MockFavoritesApi]).
class HttpFavoritesApi implements FavoritesApi {
  HttpFavoritesApi(this._client);

  final FavoritesHttpClient _client;

  @override
  Future<List<Event>> fetchFavorites() async => [
    for (final (event, _) in await _client.fetchFavorites()) event,
  ];

  @override
  Future<void> addFavorite(Event event) => _client.add(event.id);

  @override
  Future<void> removeFavorite(String eventId) => _client.remove(eventId);

  /// No hi ha endpoint propi: es consulta la llista.
  @override
  Future<bool> isFavorite(String eventId) async =>
      (await _client.fetchFavorites()).any((f) => f.$1.id == eventId);
}

/// Alertes dels preferits contra el backend real (substitueix
/// [MockFavoriteAlertsApi]). L'estat surt del mateix `GET` dels preferits.
class HttpFavoriteAlertsApi implements FavoriteAlertsApi {
  HttpFavoriteAlertsApi(this._client);

  final FavoritesHttpClient _client;

  @override
  Future<Set<String>> fetchMuted() async => {
    for (final (event, alertsEnabled) in await _client.fetchFavorites())
      if (!alertsEnabled) event.id,
  };

  @override
  Future<void> setAlertsEnabled(String eventId, {required bool enabled}) =>
      _client.setAlertsEnabled(eventId, enabled: enabled);
}
