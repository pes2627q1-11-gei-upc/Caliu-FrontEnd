import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';

class AuthApiException implements Exception {
  const AuthApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class AuthenticatedProfile {
  const AuthenticatedProfile({
    required this.id,
    required this.username,
    required this.email,
    required this.preferences,
  });

  final String id;
  /// Pot ser null just després del registre (abans del PATCH /users/me).
  final String? username;
  final String email;
  final List<String> preferences;

  factory AuthenticatedProfile.fromJson(dynamic decoded) {
    if (decoded is! Map<String, dynamic> ||
        decoded['id'] is! String ||
        decoded['email'] is! String ||
        decoded['preferences'] is! List ||
        (decoded['preferences'] as List).any((value) => value is! String) ||
        (decoded['username'] != null && decoded['username'] is! String)) {
      throw const AuthApiException('El perfil rebut no té el format esperat.');
    }

    return AuthenticatedProfile(
      id: decoded['id'] as String,
      username: decoded['username'] as String?,
      email: decoded['email'] as String,
      preferences: List<String>.from(decoded['preferences'] as List),
    );
  }
}

class AuthResult {
  const AuthResult({required this.user, required this.token});

  final AuthenticatedProfile user;
  final String token;
}

class AuthApi {
  AuthApi({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      _baseUrl = baseUrl ?? apiBaseUrl;

  final http.Client _client;
  final String _baseUrl;

  /// Contracte OpenAPI: register només email+password (sense token).
  /// Després fa login i, si hi ha username, PATCH /users/me.
  Future<AuthResult> register({
    required String username,
    required String email,
    required String password,
  }) async {
    final trimmedEmail = email.trim();
    final response = await _sendCredentials('/auth/register', {
      'email': trimmedEmail,
      'password': password,
    });
    _requireSuccess(
      response,
      201,
      'No s’ha pogut crear el compte.',
      conflictMessage: 'Aquest correu electrònic ja està en ús.',
    );

    final result = await login(email: trimmedEmail, password: password);
    final trimmedUsername = username.trim();
    if (trimmedUsername.isEmpty) return result;

    final user = await updateProfile(
      token: result.token,
      username: trimmedUsername,
    );
    return AuthResult(user: user, token: result.token);
  }

  Future<AuthResult> login({
    required String email,
    required String password,
  }) async {
    final response = await _sendCredentials('/auth/login', {
      'email': email.trim(),
      'password': password,
    });
    return _parseAuthResponse(response, expectedStatus: 200);
  }

  Future<http.Response> _send(
    String method,
    String path, {
    String? token,
    Object? body,
  }) async {
    final headers = <String, String>{};
    if (token != null) headers['authorization'] = 'Bearer $token';
    if (body != null) headers['content-type'] = 'application/json';

    try {
      final uri = Uri.parse('$_baseUrl$path');
      final request = switch (method) {
        'GET' => _client.get(uri, headers: headers),
        'POST' => _client.post(
          uri,
          headers: headers,
          body: body == null ? null : jsonEncode(body),
        ),
        'PATCH' => _client.patch(
          uri,
          headers: headers,
          body: jsonEncode(body),
        ),
        'PUT' => _client.put(
          uri,
          headers: headers,
          body: jsonEncode(body),
        ),
        _ => throw StateError('Mètode HTTP no admès'),
      };
      return await request.timeout(const Duration(seconds: 15));
    } on Exception {
      throw const AuthApiException(
        'No s’ha pogut connectar amb el servidor. Comprova la connexió i torna-ho a provar.',
      );
    }
  }

  Future<http.Response> _sendCredentials(
    String path,
    Map<String, String> credentials,
  ) => _send('POST', path, body: credentials);

  AuthResult _parseAuthResponse(
    http.Response response, {
    required int expectedStatus,
  }) {
    _requireSuccess(
      response,
      expectedStatus,
      'No s’ha pogut autenticar.',
      conflictMessage: 'Aquest correu electrònic o nom d’usuari ja està en ús.',
    );
    final dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw AuthApiException(
        'El servidor ha retornat una resposta inesperada (${response.statusCode}).',
      );
    }

    if (decoded is! Map<String, dynamic> ||
        decoded['token'] is! String ||
        (decoded['token'] as String).isEmpty ||
        decoded['tokenType'] != 'Bearer' ||
        decoded['expiresIn'] is! num ||
        decoded['user'] is! Map<String, dynamic>) {
      throw const AuthApiException(
        'El servidor ha retornat una resposta d’autenticació no vàlida.',
      );
    }

    return AuthResult(
      user: AuthenticatedProfile.fromJson(decoded['user']),
      token: decoded['token'] as String,
    );
  }

  Future<AuthenticatedProfile> fetchProfile(String token) async {
    final response = await _send('GET', '/users/me', token: token);
    _requireSuccess(response, 200, 'No s’ha pogut carregar el perfil.');
    return AuthenticatedProfile.fromJson(_decode(response));
  }

  Future<AuthenticatedProfile> updateProfile({
    required String token,
    required String username,
  }) async {
    final response = await _send(
      'PATCH',
      '/users/me',
      token: token,
      body: {'username': username.trim()},
    );
    _requireSuccess(
      response,
      200,
      'No s’ha pogut actualitzar el perfil.',
      conflictMessage: 'Aquest nom d’usuari ja està en ús.',
    );
    return AuthenticatedProfile.fromJson(_decode(response));
  }

  Future<List<String>> fetchPreferences(String token) async {
    final response = await _send(
      'GET',
      '/users/me/preferences',
      token: token,
    );
    _requireSuccess(response, 200, 'No s’han pogut carregar les preferències.');
    return _parseStringList(_decode(response), 'preferences');
  }

  Future<List<String>> updatePreferences({
    required String token,
    required List<String> preferences,
  }) async {
    final response = await _send(
      'PUT',
      '/users/me/preferences',
      token: token,
      body: {'preferences': preferences},
    );
    _requireSuccess(response, 200, 'No s’han pogut desar les preferències.');
    return _parseStringList(_decode(response), 'preferences');
  }

  Future<List<String>> fetchCategories() async {
    final response = await _send('GET', '/events/categories');
    _requireSuccess(response, 200, 'No s’han pogut carregar les categories.');
    return _parseStringList(_decode(response), 'categories');
  }

  List<String> _parseStringList(dynamic decoded, String key) {
    if (decoded is! Map<String, dynamic> ||
        decoded[key] is! List ||
        (decoded[key] as List).any((value) => value is! String)) {
      throw AuthApiException(
        'La resposta de categories o preferències no té el format esperat.',
      );
    }
    return List<String>.from(decoded[key] as List);
  }

  dynamic _decode(http.Response response) {
    try {
      return jsonDecode(response.body);
    } on FormatException {
      throw AuthApiException(
        'El servidor ha retornat una resposta inesperada (${response.statusCode}).',
        statusCode: response.statusCode,
      );
    }
  }

  void _requireSuccess(
    http.Response response,
    int expected,
    String fallback, {
    String? conflictMessage,
  }) {
    if (response.statusCode == expected) return;

    final statusCode = response.statusCode;
    final message = switch (statusCode) {
      400 => _errorMessage(response) ?? 'Revisa les dades introduïdes.',
      401 => 'La sessió o les credencials no són vàlides. Inicia sessió de nou.',
      409 =>
        _errorMessage(response) ??
        conflictMessage ??
        'Aquest nom d’usuari ja està en ús.',
      429 => 'S’han fet massa intents. Espera una estona i torna-ho a provar.',
      500 => 'El servidor ha tingut un problema. Torna-ho a provar més tard.',
      _ => fallback,
    };
    throw AuthApiException(message, statusCode: statusCode);
  }

  String? _errorMessage(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic> && decoded['error'] is String) {
        return decoded['error'] as String;
      }
    } on FormatException {
      return null;
    }
    return null;
  }

  Future<void> logout(String token) async {
    final response = await _send('POST', '/auth/logout', token: token);

    if (response.statusCode != 204 && response.statusCode != 401) {
      _requireSuccess(response, 204, 'No s’ha pogut tancar la sessió.');
    }
  }
}
