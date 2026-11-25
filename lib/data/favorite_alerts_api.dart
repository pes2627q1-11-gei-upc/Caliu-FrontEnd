import 'auth_session.dart';
import 'favorites_api.dart';
import 'favorites_http_api.dart';

/// Alertes dels esdeveniments guardats: es poden silenciar d'un en un
/// (H.U #52). Per defecte, tots els preferits tenen les alertes actives.
///
/// Endpoints del backend (OpenAPI): cada item de `GET /users/me/favorites`
/// inclou `notificacionsActives`, i es canvia amb
/// `PATCH /users/me/favorites/{eventId}`. Vegeu [HttpFavoriteAlertsApi].
abstract interface class FavoriteAlertsApi {
  /// Ids dels preferits que tenen les alertes silenciades.
  Future<Set<String>> fetchMuted();

  /// Activa o silencia les alertes d'un sol preferit.
  Future<void> setAlertsEnabled(String eventId, {required bool enabled});
}

/// Instància que fa servir l'app: el backend real (tasca #207).
FavoriteAlertsApi createFavoriteAlertsApi({AuthSessionStore? session}) =>
    HttpFavoriteAlertsApi(FavoritesHttpClient(session: session));

/// Implementació en memòria, per als tests.
class MockFavoriteAlertsApi implements FavoriteAlertsApi {
  MockFavoriteAlertsApi({
    this.session,
    Set<String>? muted,
    this.latency = const Duration(milliseconds: 300),
  }) : _muted = {...?muted};

  /// Si és null no es comprova la sessió.
  final AuthSessionStore? session;

  /// Retard artificial per simular la xarxa (zero als tests).
  final Duration latency;

  final Set<String> _muted;

  @override
  Future<Set<String>> fetchMuted() async {
    await _simulateRequest();
    return Set.unmodifiable(_muted);
  }

  @override
  Future<void> setAlertsEnabled(String eventId, {required bool enabled}) async {
    await _simulateRequest();
    if (enabled) {
      _muted.remove(eventId);
    } else {
      _muted.add(eventId);
    }
  }

  Future<void> _simulateRequest() async {
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    final session = this.session;
    if (session == null) return;
    final token = await session.readToken();
    if (token == null || token.isEmpty) {
      throw const FavoritesApiException(
        'Cal iniciar sessió per gestionar les alertes',
        statusCode: 401,
      );
    }
  }
}
