import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';
import 'activity_api.dart';
import 'attended_api.dart';
import 'auth_session.dart';
import 'event.dart';

/// Lectura de les assistències del compte (tasca #229). Comú a l'activitat
/// (H.U #36) i a l'historial (H.U #51), que són dues llistes de només lectura
/// amb la mateixa autenticació.
class AttendanceHttpClient {
  AttendanceHttpClient({
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

  /// `GET path` amb el token. Retorna la llista `items` o llança l'error que
  /// construeix [error] (cada API té la seva excepció).
  Future<List<Map<String, dynamic>>> fetchItems(
    String path, {
    required Exception Function(String message, int? statusCode) error,
    required String unauthorizedMessage,
    required String fallbackMessage,
  }) async {
    final String? token;
    try {
      token = await _session.readToken();
    } on Exception {
      throw error(unauthorizedMessage, 401);
    }
    // Sense sessió no cal ni fer la petició.
    if (token == null || token.isEmpty) throw error(unauthorizedMessage, 401);

    final http.Response response;
    try {
      response = await _client
          .get(
            Uri.parse('$_baseUrl$path'),
            headers: {'authorization': 'Bearer $token'},
          )
          .timeout(_timeout);
    } on Exception {
      throw error(
        'No s\'ha pogut connectar amb el servidor. Comprova la connexió i '
        'torna-ho a provar.',
        null,
      );
    }

    if (response.statusCode == 401) throw error(unauthorizedMessage, 401);
    if (response.statusCode != 200) {
      throw error(fallbackMessage, response.statusCode);
    }
    try {
      final decoded = jsonDecode(response.body);
      final items = decoded is Map<String, dynamic> ? decoded['items'] : null;
      if (items is List) {
        return items.whereType<Map<String, dynamic>>().toList();
      }
    } on FormatException {
      // Cau a l'error de sota.
    }
    throw error('La resposta del servidor no té el format esperat', null);
  }
}

/// Activitat (assistències recents) contra el backend real: `GET
/// /users/me/activity` → `{ items: [{ id, event, attendedAt }] }`.
class HttpActivityApi implements ActivityApi {
  HttpActivityApi(this._client);

  final AttendanceHttpClient _client;

  @override
  Future<List<ActivityEntry>> fetchActivity() async {
    final items = await _client.fetchItems(
      '/users/me/activity',
      error: (message, status) =>
          ActivityApiException(message, statusCode: status),
      unauthorizedMessage: 'Cal iniciar sessió per veure la teva activitat',
      fallbackMessage: 'No s\'ha pogut carregar l\'activitat',
    );
    final entries = <ActivityEntry>[];
    for (final item in items) {
      final id = item['id'];
      final event = item['event'];
      final at = DateTime.tryParse(item['attendedAt']?.toString() ?? '');
      // Les entrades incompletes es descarten en lloc de trencar la llista.
      if (id is! String || event is! Map<String, dynamic> || at == null) {
        continue;
      }
      entries.add(
        ActivityEntry(id: id, event: Event.fromJson(event), at: at.toLocal()),
      );
    }
    return List.unmodifiable(entries);
  }
}

/// Historial (esdeveniments acabats als quals has anat) contra el backend
/// real: `GET /users/me/attended` → `{ items: [Event] }`.
class HttpAttendedApi implements AttendedApi {
  HttpAttendedApi(this._client);

  final AttendanceHttpClient _client;

  @override
  Future<List<Event>> fetchAttended() async {
    final items = await _client.fetchItems(
      '/users/me/attended',
      error: (message, status) =>
          AttendedApiException(message, statusCode: status),
      unauthorizedMessage: 'Cal iniciar sessió per veure el teu historial',
      fallbackMessage: 'No s\'ha pogut carregar l\'historial',
    );
    return List.unmodifiable(items.map(Event.fromJson));
  }
}
