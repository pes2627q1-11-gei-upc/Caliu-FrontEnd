import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';
import 'password_reset_api.dart';

/// Recuperació de contrasenya contra el backend real (tasca #232), substitueix
/// [MockPasswordResetApi]. No cal sessió: és precisament per qui no pot entrar.
///
/// - `POST /auth/forgot-password` → `{ email }`, 202 (existeixi o no el
///   compte). 503 si el servei de correu no està configurat.
/// - `POST /auth/reset-password` → `{ token, password }`, 204. 400 si el codi
///   és invàlid o ha caducat, o si la contrasenya no és vàlida.
/// - Tots dos: 429 en superar 5 intents per IP en 15 minuts.
class HttpPasswordResetApi implements PasswordResetApi {
  HttpPasswordResetApi({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      _baseUrl = baseUrl ?? apiBaseUrl;

  final http.Client _client;
  final String _baseUrl;

  static const _rateLimited = PasswordResetException(
    'Massa intents. Espera uns minuts i torna-ho a provar.',
    statusCode: 429,
  );

  @override
  Future<void> requestReset(String email) async {
    final response = await _post('/auth/forgot-password', {
      'email': email.trim(),
    });
    switch (response.statusCode) {
      case 202:
        return;
      case 429:
        throw _rateLimited;
      case 503:
        throw const PasswordResetException(
          'La recuperació de contrasenya no està disponible ara mateix. '
          'Torna-ho a provar més tard.',
          statusCode: 503,
        );
      case 400:
        throw const PasswordResetException(
          'Revisa el correu electrònic i torna-ho a provar.',
          statusCode: 400,
        );
    }
    throw PasswordResetException(
      'No s\'ha pogut enviar el correu. Torna-ho a provar.',
      statusCode: response.statusCode,
    );
  }

  @override
  Future<void> resetPassword({
    required String token,
    required String password,
  }) async {
    final response = await _post('/auth/reset-password', {
      // El codi del correu és hexadecimal en minúscules.
      'token': token.trim().toLowerCase(),
      'password': password,
    });
    switch (response.statusCode) {
      case 204:
        return;
      case 429:
        throw _rateLimited;
      case 400:
        throw PasswordResetException(
          _serverMessage(response) ??
              'El codi no és vàlid o ha caducat. Demana\'n un de nou.',
          statusCode: 400,
        );
    }
    throw PasswordResetException(
      'No s\'ha pogut canviar la contrasenya. Torna-ho a provar.',
      statusCode: response.statusCode,
    );
  }

  Future<http.Response> _post(String path, Map<String, String> body) async {
    try {
      return await _client
          .post(
            Uri.parse('$_baseUrl$path'),
            headers: {'content-type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));
    } on Exception {
      throw const PasswordResetException(
        'No s\'ha pogut connectar amb el servidor. Comprova la connexió i '
        'torna-ho a provar.',
      );
    }
  }

  /// Missatge d'error del backend (`{ "error": "..." }`), si n'hi ha.
  String? _serverMessage(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      final error = decoded is Map<String, dynamic> ? decoded['error'] : null;
      if (error is String && error.trim().isNotEmpty) return error.trim();
    } on FormatException {
      // Sense missatge llegible.
    }
    return null;
  }
}
