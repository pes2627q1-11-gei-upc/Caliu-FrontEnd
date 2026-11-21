import 'auth_session.dart';
import 'favorites_api.dart';

/// Alertes dels esdeveniments guardats: es poden silenciar d'un en un
/// (H.U #52). Per defecte, tots els preferits tenen les alertes actives.
///
/// El backend encara no ho exposa (tasca #170: camp `notificacionsActives`
/// al registre del preferit + PATCH). Proposta de contracte (pendent de
/// confirmar a l'OpenAPI del backend):
/// - `GET /users/me/favorites` → cada item inclou `"notificacionsActives"`
/// - `PATCH /users/me/favorites/{eventId}` → body
///   `{ "notificacionsActives": true | false }`
abstract interface class FavoriteAlertsApi {
  /// Ids dels preferits que tenen les alertes silenciades.
  Future<Set<String>> fetchMuted();

  /// Activa o silencia les alertes d'un sol preferit.
  Future<void> setAlertsEnabled(String eventId, {required bool enabled});
}

/// Instància que fa servir l'app. Quan el backend estigui llest, aquí es
/// canviarà la implementació simulada per la HTTP.
FavoriteAlertsApi createFavoriteAlertsApi({AuthSessionStore? session}) =>
    MockFavoriteAlertsApi(session: session ?? AuthSession());

/// Implementació en memòria mentre no hi ha backend.
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
