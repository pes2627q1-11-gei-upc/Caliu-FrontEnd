import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';
import 'auth_session.dart';
import 'users_api.dart';

/// Perfil públic, seguir i llistes de seguidors contra el backend real
/// (substitueix [MockUsersApi]).
///
/// Endpoints (OpenAPI del backend):
/// - `GET /users/{username}` → `{ id, username, avatarUrl, sharedEventsCount,
///   isFollowing }`
/// - `POST` i `DELETE /users/{id}/follow` → 204 (idempotents)
/// - `GET /users/{id}/followers` i `GET /users/{id}/following` →
///   `{ items: [{ id, username }], total }`
///
/// El backend no té `/users/me/followers`: per al compte propi
/// ([ownProfileId]) es busca primer l'id real amb `GET /users/me`.
class HttpUsersApi implements UsersApi {
  HttpUsersApi({
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

  /// Id real del compte propi, desat per al token amb què s'ha llegit.
  (String token, String id)? _ownId;

  @override
  Future<PublicUser> fetchPublicProfile(String username) async {
    final response = await _send(
      'GET',
      '/users/${Uri.encodeComponent(username)}',
      unauthorizedMessage:
          'Cal iniciar sessió per veure perfils d\'altres usuaris',
    );
    // Un nom invàlid (400) tampoc pot correspondre a cap usuari.
    if (response.statusCode == 400 || response.statusCode == 404) {
      throw _notFound;
    }
    _requireStatus(response, 200, 'No s\'ha pogut carregar el perfil');
    final json = _decodeMap(
      response,
      'El perfil rebut no té el format esperat.',
    );
    final user = PublicUser.fromJson(json);
    return PublicUser(
      id: user.id,
      username: user.username,
      avatarUrl: _absoluteUrl(user.avatarUrl),
      sharedEventsCount: user.sharedEventsCount,
      isFollowing: user.isFollowing,
    );
  }

  @override
  Future<void> follow(String userId) => _followRequest('POST', userId);

  @override
  Future<void> unfollow(String userId) => _followRequest('DELETE', userId);

  @override
  Future<List<PublicUser>> fetchFollowers(String userId) =>
      _fetchList(userId, 'followers');

  @override
  Future<List<PublicUser>> fetchFollowing(String userId) =>
      _fetchList(userId, 'following');

  Future<void> _followRequest(String method, String userId) async {
    final response = await _send(
      method,
      '/users/${Uri.encodeComponent(userId)}/follow',
      unauthorizedMessage: 'Cal iniciar sessió per seguir altres usuaris',
    );
    switch (response.statusCode) {
      case 204:
        return;
      case 400:
        throw const UsersApiException(
          'No et pots seguir a tu mateix',
          statusCode: 400,
        );
      case 404:
        throw _notFound;
    }
    _requireStatus(response, 204, 'No s\'ha pogut actualitzar el seguiment');
  }

  Future<List<PublicUser>> _fetchList(String userId, String list) async {
    final id = userId == ownProfileId ? await _resolveOwnId() : userId;
    final response = await _send(
      'GET',
      '/users/${Uri.encodeComponent(id)}/$list',
      unauthorizedMessage: 'Cal iniciar sessió per veure les llistes',
    );
    if (response.statusCode == 400 || response.statusCode == 404) {
      throw _notFound;
    }
    _requireStatus(response, 200, 'No s\'han pogut carregar les llistes');
    final json = _decodeMap(response, 'La llista no té el format esperat.');
    final items = json['items'];
    if (items is! List) {
      throw const UsersApiException('La llista no té el format esperat.');
    }
    return List.unmodifiable([
      for (final item in items.whereType<Map<String, dynamic>>())
        if (item['id'] is String && item['username'] is String)
          PublicUser(
            id: item['id'] as String,
            username: item['username'] as String,
          ),
    ]);
  }

  /// Id real del compte autenticat (`GET /users/me`), desat per al token.
  Future<String> _resolveOwnId() async {
    final token = await _readToken();
    final cached = _ownId;
    if (cached != null && cached.$1 == token) return cached.$2;
    final response = await _send(
      'GET',
      '/users/me',
      unauthorizedMessage: 'Cal iniciar sessió per veure les llistes',
    );
    _requireStatus(response, 200, 'No s\'ha pogut carregar el teu perfil');
    final id = _decodeMap(
      response,
      'El perfil rebut no té el format esperat.',
    )['id'];
    if (id is! String) {
      throw const UsersApiException('El perfil rebut no té el format esperat.');
    }
    _ownId = (token, id);
    return id;
  }

  static const _notFound = UsersApiException(
    'Aquest usuari no existeix',
    statusCode: 404,
  );

  Future<String> _readToken({String? unauthorizedMessage}) async {
    final String? token;
    try {
      token = await _session.readToken();
    } on Exception {
      throw UsersApiException(
        unauthorizedMessage ?? 'Cal iniciar sessió',
        statusCode: 401,
      );
    }
    if (token == null || token.isEmpty) {
      throw UsersApiException(
        unauthorizedMessage ?? 'Cal iniciar sessió',
        statusCode: 401,
      );
    }
    return token;
  }

  Future<http.Response> _send(
    String method,
    String path, {
    required String unauthorizedMessage,
  }) async {
    // Sense sessió no cal ni fer la petició.
    final token = await _readToken(unauthorizedMessage: unauthorizedMessage);
    final headers = {'authorization': 'Bearer $token'};
    final uri = Uri.parse('$_baseUrl$path');
    final http.Response response;
    try {
      response = await switch (method) {
        'GET' => _client.get(uri, headers: headers),
        'POST' => _client.post(uri, headers: headers),
        'DELETE' => _client.delete(uri, headers: headers),
        _ => throw StateError('Mètode HTTP no admès: $method'),
      }.timeout(_timeout);
    } on Exception {
      throw const UsersApiException(
        'No s\'ha pogut connectar amb el servidor. Comprova la connexió i '
        'torna-ho a provar.',
      );
    }
    if (response.statusCode == 401) {
      throw UsersApiException(unauthorizedMessage, statusCode: 401);
    }
    return response;
  }

  void _requireStatus(http.Response response, int expected, String fallback) {
    if (response.statusCode == expected) return;
    throw UsersApiException(fallback, statusCode: response.statusCode);
  }

  Map<String, dynamic> _decodeMap(http.Response response, String message) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) return decoded;
    } on FormatException {
      // Cau a l'error de sota.
    }
    throw UsersApiException(message);
  }

  /// Les fotos poden arribar amb una ruta relativa al servidor.
  String? _absoluteUrl(String? url) {
    if (url == null || url.startsWith('http')) return url;
    return '$_baseUrl${url.startsWith('/') ? '' : '/'}$url';
  }
}
