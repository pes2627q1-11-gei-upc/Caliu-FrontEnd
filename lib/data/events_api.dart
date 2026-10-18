import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';
import 'event.dart';

class EventsApiException implements Exception {
  EventsApiException(this.message);
  final String message;

  @override
  String toString() => message;
}

class EventsApi {
  EventsApi({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        _baseUrl = baseUrl ?? apiBaseUrl;

  final http.Client _client;
  final String _baseUrl;

  Future<List<Event>> fetchNearby({
    required double lat,
    required double lng,
    double radiusKm = 15,
    int limit = 50,
  }) async {
    final uri = Uri.parse('$_baseUrl/events').replace(
      queryParameters: {
        'lat': lat.toString(),
        'lng': lng.toString(),
        'radiusKm': radiusKm.toString(),
        'limit': limit.toString(),
      },
    );

    final decoded = await _getJson(uri);
    if (decoded is! Map<String, dynamic>) {
      throw EventsApiException('Resposta inesperada de /events');
    }

    final items = decoded['items'];
    if (items is! List) return const [];

    return items
        .whereType<Map<String, dynamic>>()
        .map(Event.fromJson)
        .toList();
  }

  Future<Event> fetchById(String id) async {
    final uri = Uri.parse('$_baseUrl/events/$id');
    final decoded = await _getJson(uri);
    if (decoded is! Map<String, dynamic>) {
      throw EventsApiException('Resposta inesperada de /events/$id');
    }
    return Event.fromJson(decoded);
  }

  Future<dynamic> _getJson(Uri uri) async {
    late final http.Response response;
    try {
      response = await _client.get(uri).timeout(const Duration(seconds: 15));
    } on Exception catch (e) {
      throw EventsApiException('No s\'ha pogut connectar a $_baseUrl ($e)');
    }

    if (response.statusCode == 404) {
      throw EventsApiException('Esdeveniment no trobat');
    }

    if (response.statusCode != 200) {
      String detail = response.body;
      try {
        final body = jsonDecode(response.body);
        if (body is Map && body['error'] != null) {
          detail = body['error'].toString();
        }
      } on FormatException {
        // ignore
      }
      throw EventsApiException('API ${response.statusCode}: $detail');
    }

    return jsonDecode(response.body);
  }
}
