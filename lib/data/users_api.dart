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
    this.isFollowing = false,
  });

  final String id;
  final String username;
  final String? avatarUrl;

  /// Actes als quals heu assistit tots dos.
  final int sharedEventsCount;

  /// L'usuari autenticat ja el segueix (H.U #61).
  final bool isFollowing;

  PublicUser copyWith({bool? isFollowing}) => PublicUser(
    id: id,
    username: username,
    avatarUrl: avatarUrl,
    sharedEventsCount: sharedEventsCount,
    isFollowing: isFollowing ?? this.isFollowing,
  );

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
      isFollowing: json['isFollowing'] == true,
    );
  }
}

/// Perfils públics dels usuaris de la comunitat.
///
/// El backend encara no l'exposa (tasca #178). Proposta de contracte
/// (pendent de confirmar a l'OpenAPI del backend):
/// - `GET /users/{username}` →
///   `{ "id", "username", "avatarUrl", "sharedEventsCount", "isFollowing" }`
///   (sense email)
/// - `POST /users/{id}/follow` i `DELETE /users/{id}/follow` (H.U #61,
///   tasca #181): seguir és idempotent i no es pot seguir un mateix
/// - 404 si l'usuari no existeix; 401 sense JWT vàlid
abstract interface class UsersApi {
  Future<PublicUser> fetchPublicProfile(String username);

  /// Comença a seguir l'usuari [userId]. Si ja el segueix, no fa res.
  Future<void> follow(String userId);

  /// Deixa de seguir l'usuari [userId]. Si no el seguia, no fa res.
  Future<void> unfollow(String userId);
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
    this.currentUserId,
  }) : _users = {for (final u in seed ?? samplePublicUsers) u.username: u} {
    _following.addAll(
      _users.values.where((u) => u.isFollowing).map((u) => u.id),
    );
  }

  /// Id de l'usuari autenticat, per rebutjar que se segueixi a si mateix.
  final String? currentUserId;

  /// Relació unidireccional: ids dels usuaris que segueix l'autenticat.
  final Set<String> _following = {};

  /// Si és null no es comprova la sessió.
  final AuthSessionStore? session;

  /// Retard artificial per simular la xarxa (zero als tests).
  final Duration latency;

  final Map<String, PublicUser> _users;

  @override
  Future<PublicUser> fetchPublicProfile(String username) async {
    await _simulateRequest(
      'Cal iniciar sessió per veure perfils d\'altres usuaris',
    );
    final user = _users[username];
    if (user == null) {
      throw const UsersApiException(
        'Aquest usuari no existeix',
        statusCode: 404,
      );
    }
    return user.copyWith(isFollowing: _following.contains(user.id));
  }

  @override
  Future<void> follow(String userId) async {
    await _simulateRequest('Cal iniciar sessió per seguir altres usuaris');
    _requireUser(userId);
    if (userId == currentUserId) {
      throw const UsersApiException(
        'No et pots seguir a tu mateix',
        statusCode: 400,
      );
    }
    _following.add(userId);
  }

  @override
  Future<void> unfollow(String userId) async {
    await _simulateRequest('Cal iniciar sessió per seguir altres usuaris');
    _requireUser(userId);
    _following.remove(userId);
  }

  void _requireUser(String userId) {
    if (!_users.values.any((u) => u.id == userId)) {
      throw const UsersApiException(
        'Aquest usuari no existeix',
        statusCode: 404,
      );
    }
  }

  Future<void> _simulateRequest(String unauthorizedMessage) async {
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    final session = this.session;
    if (session == null) return;
    final token = await session.readToken();
    if (token == null || token.isEmpty) {
      throw UsersApiException(unauthorizedMessage, statusCode: 401);
    }
  }
}

/// Usuaris simulats de la comunitat.
const samplePublicUsers = [
  PublicUser(id: 'mock-user-1', username: 'laia_museus', sharedEventsCount: 4),
  PublicUser(id: 'mock-user-2', username: 'pau.fires', sharedEventsCount: 1),
  PublicUser(id: 'mock-user-3', username: 'marta_concerts'),
];
