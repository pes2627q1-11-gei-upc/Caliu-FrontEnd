import 'auth_session.dart';

class UsersApiException implements Exception {
  const UsersApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  bool get isUnauthorized => statusCode == 401;

  bool get isNotFound => statusCode == 404;

  @override
  String toString() => message;
}

/// Perfil públic d'un altre usuari (H.U #60). Només conté dades públiques:
/// mai l'email ni cap altre camp privat.
class PublicUser {
  const PublicUser({
    required this.id,
    required this.username,
    this.avatarUrl,
    this.sharedEventsCount = 0,
  });

  final String id;
  final String username;
  final String? avatarUrl;

  /// Actes als quals heu assistit tots dos.
  final int sharedEventsCount;

  /// Llegeix el DTO públic. Ignora qualsevol altre camp que pogués arribar.
  factory PublicUser.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final username = json['username'];
    if (id is! String || username is! String) {
      throw const UsersApiException('El perfil rebut no té el format esperat.');
    }
    final avatar = json['avatarUrl'];
    final shared = json['sharedEventsCount'];
    return PublicUser(
      id: id,
      username: username,
      avatarUrl: avatar is String && avatar.isNotEmpty ? avatar : null,
      sharedEventsCount: shared is num ? shared.toInt() : 0,
    );
  }
}

/// Perfils públics dels usuaris de la comunitat.
///
/// El backend encara no l'exposa (tasca #178). Proposta de contracte
/// (pendent de confirmar a l'OpenAPI del backend):
/// - `GET /users/{username}` →
///   `{ "id", "username", "avatarUrl", "sharedEventsCount" }` (sense email)
/// - 404 si l'usuari no existeix; 401 sense JWT vàlid
abstract interface class UsersApi {
  Future<PublicUser> fetchPublicProfile(String username);
}

/// Instància que fa servir l'app. Quan el backend estigui llest, aquí es
/// canviarà la implementació simulada per la HTTP.
UsersApi createUsersApi({AuthSessionStore? session}) =>
    MockUsersApi(session: session ?? AuthSession());

/// Implementació amb dades simulades mentre no hi ha backend.
class MockUsersApi implements UsersApi {
  MockUsersApi({
    this.session,
    List<PublicUser>? seed,
    this.latency = const Duration(milliseconds: 300),
  }) : _users = {for (final u in seed ?? samplePublicUsers) u.username: u};

  /// Si és null no es comprova la sessió.
  final AuthSessionStore? session;

  /// Retard artificial per simular la xarxa (zero als tests).
  final Duration latency;

  final Map<String, PublicUser> _users;

  @override
  Future<PublicUser> fetchPublicProfile(String username) async {
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    final session = this.session;
    if (session != null) {
      final token = await session.readToken();
      if (token == null || token.isEmpty) {
        throw const UsersApiException(
          'Cal iniciar sessió per veure perfils d\'altres usuaris',
          statusCode: 401,
        );
      }
    }
    final user = _users[username];
    if (user == null) {
      throw const UsersApiException(
        'Aquest usuari no existeix',
        statusCode: 404,
      );
    }
    return user;
  }
}

/// Usuaris simulats de la comunitat.
const samplePublicUsers = [
  PublicUser(id: 'mock-user-1', username: 'laia_museus', sharedEventsCount: 4),
  PublicUser(id: 'mock-user-2', username: 'pau.fires', sharedEventsCount: 1),
  PublicUser(id: 'mock-user-3', username: 'marta_concerts'),
];
