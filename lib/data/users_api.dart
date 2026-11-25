import 'auth_session.dart';
import 'users_http_api.dart';

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
/// Endpoints del backend (OpenAPI); vegeu [HttpUsersApi]:
/// - `GET /users/{username}` →
///   `{ "id", "username", "avatarUrl", "sharedEventsCount", "isFollowing" }`
///   (sense email)
/// - `POST /users/{id}/follow` i `DELETE /users/{id}/follow` (H.U #61,
///   tasca #181): seguir és idempotent i no es pot seguir un mateix
/// - `GET /users/{id}/followers` i `GET /users/{id}/following` (H.U #62,
///   tasca #183) → `{ "items": [{ id, username }], total }`
/// - 404 si l'usuari no existeix; 401 sense JWT vàlid
abstract interface class UsersApi {
  Future<PublicUser> fetchPublicProfile(String username);

  /// Comença a seguir l'usuari [userId]. Si ja el segueix, no fa res.
  Future<void> follow(String userId);

  /// Deixa de seguir l'usuari [userId]. Si no el seguia, no fa res.
  Future<void> unfollow(String userId);

  /// Usuaris que segueixen [userId].
  Future<List<PublicUser>> fetchFollowers(String userId);

  /// Usuaris als quals segueix [userId].
  Future<List<PublicUser>> fetchFollowing(String userId);
}

/// Identificador explícit del compte propi per a les llistes de seguidors i
/// seguits (revisió de la PR #32). El perfil propi el fa servir en lloc de
/// l'id real perquè no depengui de com el backend identifica l'usuari: la
/// implementació HTTP el traduirà a `/users/me/followers` i
/// `/users/me/following`, o a l'id del token.
const ownProfileId = 'me';

/// Instància que fa servir l'app: el backend real.
UsersApi createUsersApi({AuthSessionStore? session}) =>
    HttpUsersApi(session: session);

/// Implementació amb dades simulades, per als tests.
///
/// Guarda un graf de seguiments unidireccional (seguidor → seguits). L'usuari
/// autenticat és [currentUserId] o, si no se'n dona cap, [ownProfileId]. Les
/// llistes només accepten ids d'usuaris coneguts o [ownProfileId]: qualsevol
/// altre id és un 404.
class MockUsersApi implements UsersApi {
  MockUsersApi({
    this.session,
    List<PublicUser>? seed,
    Map<String, Set<String>>? follows,
    this.latency = const Duration(milliseconds: 300),
    this.currentUserId,
  }) : _users = {for (final u in seed ?? samplePublicUsers) u.username: u} {
    final graph = follows ?? (seed == null ? sampleFollows : null);
    if (graph != null) {
      graph.forEach((follower, followed) => _graph[follower] = {...followed});
    } else {
      _graph[_me] = {
        for (final u in _users.values)
          if (u.isFollowing) u.id,
      };
    }
  }

  /// Id de l'usuari autenticat, per rebutjar que se segueixi a si mateix.
  final String? currentUserId;

  /// Si és null no es comprova la sessió.
  final AuthSessionStore? session;

  /// Retard artificial per simular la xarxa (zero als tests).
  final Duration latency;

  final Map<String, PublicUser> _users;

  /// Seguidor → ids dels usuaris que segueix.
  final Map<String, Set<String>> _graph = {};

  String get _me => currentUserId ?? ownProfileId;

  Set<String> get _myFollowing => _graph.putIfAbsent(_me, () => {});

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
    return user.copyWith(isFollowing: _myFollowing.contains(user.id));
  }

  @override
  Future<void> follow(String userId) async {
    await _simulateRequest('Cal iniciar sessió per seguir altres usuaris');
    _requireUser(userId);
    if (userId == _me) {
      throw const UsersApiException(
        'No et pots seguir a tu mateix',
        statusCode: 400,
      );
    }
    _myFollowing.add(userId);
  }

  @override
  Future<void> unfollow(String userId) async {
    await _simulateRequest('Cal iniciar sessió per seguir altres usuaris');
    _requireUser(userId);
    _myFollowing.remove(userId);
  }

  @override
  Future<List<PublicUser>> fetchFollowers(String userId) async {
    await _simulateRequest('Cal iniciar sessió per veure els seguidors');
    final key = _resolve(userId);
    return List.unmodifiable([
      for (final MapEntry(key: follower, value: followed) in _graph.entries)
        if (followed.contains(key)) ?_userById(follower),
    ]);
  }

  @override
  Future<List<PublicUser>> fetchFollowing(String userId) async {
    await _simulateRequest('Cal iniciar sessió per veure els seguits');
    final key = _resolve(userId);
    return List.unmodifiable([
      for (final id in _graph[key] ?? const <String>{}) ?_userById(id),
    ]);
  }

  PublicUser? _userById(String id) {
    for (final user in _users.values) {
      if (user.id == id) {
        return user.copyWith(isFollowing: _myFollowing.contains(id));
      }
    }
    return null;
  }

  /// Clau del graf per a [userId]: un usuari conegut o el compte propi
  /// ([ownProfileId]). Qualsevol altre id és un 404.
  String _resolve(String userId) {
    if (userId == ownProfileId || userId == _me) return _me;
    if (_users.values.any((u) => u.id == userId)) return userId;
    throw const UsersApiException('Aquest usuari no existeix', statusCode: 404);
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

/// Usuaris simulats de la comunitat, inclòs el propi compte ([ownProfileId]).
const samplePublicUsers = [
  PublicUser(id: ownProfileId, username: 'jo'),
  PublicUser(id: 'mock-user-1', username: 'laia_museus', sharedEventsCount: 4),
  PublicUser(id: 'mock-user-2', username: 'pau.fires', sharedEventsCount: 1),
  PublicUser(id: 'mock-user-3', username: 'marta_concerts'),
];

/// Seguiments simulats (seguidor → seguits).
const sampleFollows = <String, Set<String>>{
  ownProfileId: {'mock-user-1'},
  'mock-user-1': {ownProfileId, 'mock-user-2'},
  'mock-user-2': {'mock-user-1'},
  'mock-user-3': {ownProfileId, 'mock-user-1'},
};
