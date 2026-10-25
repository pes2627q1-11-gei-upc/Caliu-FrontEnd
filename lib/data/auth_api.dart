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

class RegistrationResult {
  const RegistrationResult({
    required this.token,
    required this.username,
    required this.email,
  });

  final String token;
  final String username;
  final String email;
}

class AuthenticatedProfile {
  const AuthenticatedProfile({
    required this.id,
    required this.username,
    required this.email,
    required this.preferences,
  });

  final String id;
  final String username;
  final String email;
  final List<String> preferences;
}

class AuthApi {
  AuthApi({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      _baseUrl = baseUrl ?? apiBaseUrl;

  final http.Client _client;
  final String _baseUrl;

  Future<RegistrationResult> register({
    required String username,
    required String email,
    required String password,
  }) async {
    final response = await _sendCredentials('/auth/register', {
      'username': username.trim(),
      'email': email.trim(),
      'password': password,
    });
    return _parseAuthResponse(response, expectedStatus: 201);
  }

  Future<RegistrationResult> login({
    required String email,
    required String password,
  }) async {
    final response = await _sendCredentials('/auth/login', {
      'email': email.trim(),
      'password': password,
    });
    return _parseAuthResponse(response, expectedStatus: 200);
  }

  Future<http.Response> _sendCredentials(
    String path,
    Map<String, String> credentials,
  ) async {
    late final http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse('$_baseUrl$path'),
            headers: {'content-type': 'application/json'},
            body: jsonEncode(credentials),
          )
          .timeout(const Duration(seconds: 15));
    } on Exception catch (error) {
      throw AuthApiException(
        'No s’ha pogut connectar amb el servidor. Comprova la connexió i torna-ho a provar. ($error)',
      );
    }
    return response;
  }

  RegistrationResult _parseAuthResponse(
    http.Response response, {
    required int expectedStatus,
  }) {
    final dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw AuthApiException(
        'El servidor ha retornat una resposta inesperada (${response.statusCode}).',
      );
    }

    if (response.statusCode != expectedStatus) {
      final detail = decoded is Map ? decoded['error']?.toString() : null;
      if (response.statusCode == 409) {
        throw const AuthApiException(
          'Aquest correu electrònic o nom d’usuari ja està en ús.',
        );
      }
      if (response.statusCode == 401) {
        throw AuthApiException(
          detail ?? 'El correu electrònic o la contrasenya són incorrectes.',
          statusCode: response.statusCode,
        );
      }
      if (response.statusCode == 400) {
        throw AuthApiException(
          detail ?? 'Revisa les dades introduïdes.',
          statusCode: response.statusCode,
        );
      }
      final fallbackMessage = expectedStatus == 200
          ? 'No s’ha pogut iniciar sessió (error ${response.statusCode}).'
          : 'No s’ha pogut crear el compte (error ${response.statusCode}).';
      throw AuthApiException(
        detail ?? fallbackMessage,
        statusCode: response.statusCode,
      );
    }

    if (decoded is! Map<String, dynamic> ||
        decoded['token'] is! String ||
        decoded['profile'] is! Map<String, dynamic>) {
      throw const AuthApiException(
        'El servidor ha creat el compte però la resposta no té el format esperat.',
      );
    }
    final profile = decoded['profile'] as Map<String, dynamic>;
    if (profile['username'] is! String || profile['email'] is! String) {
      throw const AuthApiException(
        'El servidor ha creat el compte però el perfil rebut no és vàlid.',
      );
    }

    return RegistrationResult(
      token: decoded['token'] as String,
      username: profile['username'] as String,
      email: profile['email'] as String,
    );
  }

  Future<AuthenticatedProfile> fetchProfile(String token) async {
    late final http.Response response;
    try {
      response = await _client
          .get(
            Uri.parse('$_baseUrl/profile'),
            headers: {'authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 15));
    } on Exception catch (error) {
      throw AuthApiException(
        'No s’ha pogut connectar amb el servidor. ($error)',
      );
    }

    final dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw AuthApiException(
        'El servidor ha retornat una resposta inesperada (${response.statusCode}).',
        statusCode: response.statusCode,
      );
    }

    if (response.statusCode != 200) {
      final detail = decoded is Map ? decoded['error']?.toString() : null;
      throw AuthApiException(
        detail ?? 'No s’ha pogut carregar el perfil.',
        statusCode: response.statusCode,
      );
    }
    return _parseProfile(decoded);
  }

  Future<AuthenticatedProfile> updateProfile({
    required String token,
    required String username,
  }) async {
    late final http.Response response;
    try {
      response = await _client
          .patch(
            Uri.parse('$_baseUrl/profile'),
            headers: {
              'authorization': 'Bearer $token',
              'content-type': 'application/json',
            },
            body: jsonEncode({'username': username.trim()}),
          )
          .timeout(const Duration(seconds: 15));
    } on Exception catch (error) {
      throw AuthApiException(
        'No s’ha pogut connectar amb el servidor. ($error)',
      );
    }

    final dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw AuthApiException(
        'El servidor ha retornat una resposta inesperada (${response.statusCode}).',
        statusCode: response.statusCode,
      );
    }

    if (response.statusCode != 200) {
      final detail = decoded is Map ? decoded['error']?.toString() : null;
      final message = response.statusCode == 409
          ? 'Aquest nom d’usuari ja està en ús.'
          : detail ?? 'No s’ha pogut actualitzar el perfil.';
      throw AuthApiException(message, statusCode: response.statusCode);
    }
    return _parseProfile(decoded);
  }

  AuthenticatedProfile _parseProfile(dynamic decoded) {
    if (decoded is! Map<String, dynamic> ||
        decoded['id'] is! String ||
        decoded['username'] is! String ||
        decoded['email'] is! String ||
        decoded['preferences'] is! List) {
      throw const AuthApiException('El perfil rebut no té el format esperat.');
    }

    return AuthenticatedProfile(
      id: decoded['id'] as String,
      username: decoded['username'] as String,
      email: decoded['email'] as String,
      preferences: (decoded['preferences'] as List)
          .whereType<String>()
          .toList(),
    );
  }

  Future<void> logout(String token) async {
    late final http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse('$_baseUrl/auth/logout'),
            headers: {'authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 15));
    } on Exception catch (error) {
      throw AuthApiException(
        'No s’ha pogut connectar amb el servidor. ($error)',
      );
    }

    if (response.statusCode != 204 && response.statusCode != 401) {
      throw AuthApiException(
        'No s’ha pogut tancar la sessió (error ${response.statusCode}).',
        statusCode: response.statusCode,
      );
    }
  }
}
