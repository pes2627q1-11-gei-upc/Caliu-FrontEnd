import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';
import 'event.dart';
import 'event_query.dart';

class EventsApiException implements Exception {
  EventsApiException(this.message);
  final String message;

  @override
  String toString() => message;
}

class EventPageResult {
  const EventPageResult({
    required this.items,
    required this.page,
    required this.limit,
    required this.total,
  });

  final List<Event> items;
  final int page;
  final int limit;
  final int total;
}

class EventsApi {
  EventsApi({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        _baseUrl = baseUrl ?? apiBaseUrl;

  final http.Client _client;
  final String _baseUrl;

  Future<EventPageResult> fetchEvents(EventQuery query) async {
    final uri = Uri.parse('$_baseUrl/events').replace(
      queryParameters: query.toQueryParameters(),
    );

    final decoded = await _getJson(uri);
    if (decoded is! Map<String, dynamic>) {
      throw EventsApiException('Resposta inesperada de /events');
    }

    final items = decoded['items'];
    final list = items is List
        ? items
            .whereType<Map<String, dynamic>>()
            .map(Event.fromJson)
            .toList()
        : <Event>[];

    return EventPageResult(
      items: list,
      page: decoded['page'] is num ? (decoded['page'] as num).toInt() : 1,
      limit: decoded['limit'] is num
          ? (decoded['limit'] as num).toInt()
          : query.limit,
      total: decoded['total'] is num ? (decoded['total'] as num).toInt() : list.length,
    );
  }

  Future<List<Event>> fetchNearby({
    required double lat,
    required double lng,
    double radiusKm = 15,
    int limit = 50,
  }) async {
    final page = await fetchEvents(
      EventQuery(
        lat: lat,
        lng: lng,
        radiusKm: radiusKm,
        limit: limit,
      ),
    );
    return page.items;
  }

  Future<Event> fetchById(String id) async {
    final uri = Uri.parse('$_baseUrl/events/$id');
    final decoded = await _getJson(uri);
    if (decoded is! Map<String, dynamic>) {
      throw EventsApiException('Resposta inesperada de /events/$id');
    }
    return Event.fromJson(decoded);
  }

  Future<List<String>> fetchCategories() async {
    final uri = Uri.parse('$_baseUrl/events/categories');
    final decoded = await _getJson(uri);
    if (decoded is! Map<String, dynamic>) {
      throw EventsApiException('Resposta inesperada de /events/categories');
    }
    final categories = decoded['categories'];
    if (categories is! List) return const [];
    return categories.map((e) => e.toString()).toList();
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
