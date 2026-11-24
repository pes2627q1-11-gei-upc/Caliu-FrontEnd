import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config.dart';
import 'event.dart';
import 'events_api.dart';

class RecommendationsApiException implements Exception {
  const RecommendationsApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  /// Token caducat o invàlid: cal tornar a iniciar sessió.
  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() => message;
}

/// Client de `GET /recommendations` (H.U #8, backend #120): esdeveniments
/// recomanats per a l'usuari autenticat, ordenats per puntuació.
///
/// Amb `lat` i `lng`, només dins del radi d'activitat de l'usuari i amb
/// `distanceMeters`; sense ubicació, els pròxims per data. El backend ja
/// exclou els preferits que té desats; els de l'app es filtren a la pantalla.
class RecommendationsApi {
  RecommendationsApi({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      _baseUrl = baseUrl ?? apiBaseUrl;

  /// Màxim que admet el backend (el mateix que `GET /events`).
  static const maxLimit = 100;

  final http.Client _client;
  final String _baseUrl;

  Future<EventPageResult> fetchRecommendations({
    required String token,
    double? lat,
    double? lng,
    int page = 1,
    int limit = 40,
  }) async {
    final safeLimit = limit.clamp(1, maxLimit);
    late final http.Response response;
    try {
      final uri = Uri.parse('$_baseUrl/recommendations').replace(
        queryParameters: {
          // 4 decimals (~10 m) n'hi ha prou per ordenar per proximitat.
          if (lat != null && lng != null) ...{
            'lat': lat.toStringAsFixed(4),
            'lng': lng.toStringAsFixed(4),
          },
          'page': '$page',
          'limit': '$safeLimit',
        },
      );
      response = await _client
          .get(uri, headers: {'Authorization': 'Bearer $token'})
          .timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw const RecommendationsApiException(
        'Les recomanacions estan trigant massa. Torna-ho a provar.',
      );
    } catch (_) {
      throw const RecommendationsApiException(
        'No s\'han pogut carregar les recomanacions. Comprova la connexió.',
      );
    }

    final decoded = _decode(response.body);
    if (response.statusCode != 200) {
      throw RecommendationsApiException(
        _errorMessage(response.statusCode, decoded),
        statusCode: response.statusCode,
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw const RecommendationsApiException(
        'El servidor ha retornat una resposta inesperada.',
      );
    }

    final items = <Event>[];
    final raw = decoded['items'];
    if (raw is List) {
      for (final item in raw.whereType<Map<String, dynamic>>()) {
        try {
          final event = Event.fromJson(item);
          if (event.id.isNotEmpty) items.add(event);
        } catch (_) {
          // Un esdeveniment mal format no ha de trencar tota la llista.
        }
      }
    }
    int number(String key, int fallback) =>
        decoded[key] is num ? (decoded[key] as num).toInt() : fallback;
    return EventPageResult(
      items: items,
      page: number('page', page),
      limit: number('limit', safeLimit),
      total: number('total', items.length),
    );
  }

  static dynamic _decode(String body) {
    try {
      return jsonDecode(body);
    } on FormatException {
      return null;
    }
  }

  static String _errorMessage(int status, dynamic decoded) {
    if (status == 401) return 'La sessió ha caducat. Torna a iniciar sessió.';
    if (status == 400) {
      // Un 400 només pot ser culpa de l'app: el detall va als logs.
      final detail = decoded is Map ? decoded['error'] : null;
      debugPrint('GET /recommendations 400: $detail');
    }
    return 'No s\'han pogut carregar les recomanacions ara mateix. '
        'Torna-ho a provar d\'aquí a una estona.';
  }
}
