import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';
import 'chat_filters.dart';
import 'chat_message.dart';
import 'chat_plan.dart';
import 'event.dart';

class ChatApiException implements Exception {
  const ChatApiException(
    this.message, {
    this.statusCode,
    this.code,
    this.sessionLost = false,
  });

  final String message;
  final int? statusCode;

  /// Codi d'error del backend (`code`, tasca #143 del backend), p. ex.
  /// `CHATBOT_TIMEOUT` o `EVENTS_UNAVAILABLE`. Null si no n'envia cap.
  final String? code;

  /// Token caducat o invàlid: cal tornar a iniciar sessió.
  bool get isUnauthorized => statusCode == 401;

  /// La sessió de xat ja no existeix: cal començar-ne una de nova.
  /// El backend ho indica amb `SESSION_NOT_FOUND`; sense codi, un 404 només
  /// ho és si s'havia enviat un `sessionId` (si no, falta la ruta del xat).
  final bool sessionLost;
  bool get isSessionLost => sessionLost;

  @override
  String toString() => message;
}

/// Resposta de `POST /chat/messages`.
class ChatReply {
  const ChatReply({
    required this.sessionId,
    required this.reply,
    this.events = const [],
    this.filters,
    this.plan,
    this.isFallback = false,
  });

  /// Pot ser null en una resposta alternativa d'una conversa nova: el
  /// backend no crea la sessió fins que l'assistent respon de veritat.
  final String? sessionId;
  final String reply;

  /// Resposta alternativa (`type: "fallback"`, tasca #142 del backend):
  /// l'assistent no ha pogut respondre i el backend envia un text fix amb
  /// algunes activitats. L'app ofereix tornar-ho a provar (tasca #144).
  final bool isFallback;

  /// Esdeveniments que esmenta la resposta (H.U #11, tasca #134).
  /// Camp opcional: si el backend no l'envia, la llista és buida.
  final List<Event> events;

  /// Filtres que l'assistent ha interpretat del missatge (tasca #138).
  /// Null si no n'hi ha cap o el backend no els envia.
  final ChatFilters? filters;

  /// Itinerari quan la resposta és de tipus `plan` (tasca #141).
  final ChatPlan? plan;
}

/// Una conversa de l'historial (`GET /chat/sessions`, tasca #164).
class ChatSessionSummary {
  const ChatSessionSummary({required this.id, this.title, this.lastActivityAt});

  final String id;

  /// Inici del primer missatge. Null si la sessió encara no té missatges
  /// (p. ex. una "Nova conversa" on encara no s'ha escrit res).
  final String? title;

  /// Últim missatge desat (o creació de la sessió), en hora local.
  final DateTime? lastActivityAt;

  bool get isEmpty => title == null;

  static ChatSessionSummary? fromJson(dynamic json) {
    if (json is! Map<String, dynamic>) return null;
    final id = json['id'];
    if (id is! String || id.isEmpty) return null;
    final title = json['title'];
    final last = json['lastActivityAt'] ?? json['createdAt'];
    return ChatSessionSummary(
      id: id,
      title: title is String && title.trim().isNotEmpty ? title.trim() : null,
      lastActivityAt: last is String
          ? DateTime.tryParse(last)?.toLocal()
          : null,
    );
  }
}

/// Client del xatbot (api-node, ruta protegida amb JWT).
class ChatApi {
  ChatApi({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      _baseUrl = baseUrl ?? apiBaseUrl;

  /// Mateix límit que valida el backend.
  static const maxMessageLength = 500;

  /// Gemini + Render adormit poden trigar: més marge que la resta de l'API.
  static const timeout = Duration(seconds: 90);

  final http.Client _client;
  final String _baseUrl;

  /// [locale] és l'idioma de l'app (`ca`, `es` o `en`, tasca #147): el
  /// backend el fa servir quan no pot detectar l'idioma del missatge.
  Future<ChatReply> sendMessage({
    required String token,
    required String message,
    String? sessionId,
    String? locale,
  }) async {
    final response = await _request(
      'POST',
      '/chat/messages',
      token: token,
      body: {'message': message, 'sessionId': ?sessionId, 'locale': ?locale},
    );
    if (response.statusCode != 200) {
      throw _failure(response, sessionId: sessionId);
    }

    final decoded = _decode(response.body);
    final reply = decoded is Map<String, dynamic> ? decoded['reply'] : null;
    final newSessionId = decoded is Map<String, dynamic>
        ? decoded['sessionId']
        : null;
    final isFallback =
        decoded is Map<String, dynamic> && decoded['type'] == 'fallback';
    final validSession =
        newSessionId is String || (isFallback && newSessionId == null);
    if (reply is! String || reply.trim().isEmpty || !validSession) {
      throw const ChatApiException(_unexpected);
    }
    final body = decoded as Map<String, dynamic>;
    return ChatReply(
      sessionId: newSessionId as String?,
      isFallback: isFallback,
      reply: reply.trim(),
      events: _parseEvents(body['events']),
      filters: ChatFilters.fromJson(body['filters']),
      plan: body['type'] == 'plan' ? ChatPlan.fromJson(body['plan']) : null,
    );
  }

  /// "Nova conversa" (`POST /chat/sessions`, tasca #162): crea una sessió
  /// buida i en retorna l'id. Els missatges que s'hi enviïn no porten el
  /// context de les converses anteriors, que es conserven a l'historial.
  Future<String> createSession({required String token}) async {
    final response = await _request(
      'POST',
      '/chat/sessions',
      token: token,
      body: const <String, Object>{},
    );
    if (response.statusCode != 201 && response.statusCode != 200) {
      throw _failure(response);
    }
    final decoded = _decode(response.body);
    final id = decoded is Map ? decoded['sessionId'] : null;
    if (id is! String || id.isEmpty) {
      throw const ChatApiException(_unexpected);
    }
    return id;
  }

  /// Historial de converses (`GET /chat/sessions`, tasca #164), de la més
  /// recent a la més antiga. Inclou les sessions buides.
  Future<List<ChatSessionSummary>> listSessions({required String token}) async {
    final response = await _request('GET', '/chat/sessions', token: token);
    if (response.statusCode != 200) throw _failure(response);
    final items = _items(response.body);
    return [for (final item in items) ?ChatSessionSummary.fromJson(item)];
  }

  /// Missatges desats d'una conversa (`GET /chat/sessions/{id}/messages`,
  /// tasca #164), en ordre cronològic. El backend només desa el text: les
  /// targetes, els filtres i els itineraris no es recuperen.
  Future<List<ChatMessage>> fetchMessages({
    required String token,
    required String sessionId,
  }) async {
    final response = await _request(
      'GET',
      '/chat/sessions/${Uri.encodeComponent(sessionId)}/messages',
      token: token,
    );
    if (response.statusCode != 200) {
      throw _failure(response, sessionId: sessionId);
    }
    final messages = <ChatMessage>[];
    for (final item in _items(response.body)) {
      if (item is! Map<String, dynamic>) continue;
      final id = item['id'];
      final content = item['content'];
      final role = switch (item['role']) {
        'user' => ChatRole.user,
        'assistant' => ChatRole.assistant,
        _ => null,
      };
      if (id is! String || content is! String || role == null) continue;
      if (content.trim().isEmpty) continue;
      messages.add(ChatMessage(id: 'h$id', role: role, text: content.trim()));
    }
    return messages;
  }

  /// `items` d'una resposta de llista; si no hi és, la resposta no és vàlida.
  static List<dynamic> _items(String body) {
    final decoded = _decode(body);
    final items = decoded is Map ? decoded['items'] : null;
    if (items is! List) throw const ChatApiException(_unexpected);
    return items;
  }

  Future<http.Response> _request(
    String method,
    String path, {
    required String token,
    Map<String, Object?>? body,
  }) async {
    final uri = Uri.parse('$_baseUrl$path');
    final headers = {
      'Authorization': 'Bearer $token',
      if (body != null) 'Content-Type': 'application/json',
    };
    try {
      final request = method == 'GET'
          ? _client.get(uri, headers: headers)
          : _client.post(uri, headers: headers, body: jsonEncode(body));
      return await request.timeout(timeout);
    } on TimeoutException {
      throw const ChatApiException(
        'L\'assistent està trigant massa a respondre. Torna-ho a provar.',
      );
    } on Exception {
      throw const ChatApiException(
        'No s\'ha pogut connectar amb l\'assistent. Comprova la connexió.',
      );
    }
  }

  /// Error d'una resposta no correcta. [sessionId] és la sessió que s'havia
  /// enviat: sense codi, un 404 només vol dir "sessió perduda" si n'hi havia.
  static ChatApiException _failure(
    http.Response response, {
    String? sessionId,
  }) {
    final error = _decode(response.body);
    final code = error is Map && error['code'] is String
        ? error['code'] as String
        : null;
    final sessionLost =
        code == 'SESSION_NOT_FOUND' ||
        (code == null && response.statusCode == 404 && sessionId != null);
    return ChatApiException(
      _errorMessage(response, code: code, hadSession: sessionId != null),
      statusCode: response.statusCode,
      code: code,
      sessionLost: sessionLost,
    );
  }

  static List<Event> _parseEvents(dynamic raw) {
    if (raw is! List) return const [];
    final events = <Event>[];
    for (final item in raw) {
      if (item is! Map<String, dynamic>) continue;
      try {
        final event = Event.fromJson(item);
        if (event.id.isNotEmpty) events.add(event);
      } catch (_) {
        // Un esdeveniment mal format no ha de trencar tota la resposta.
      }
    }
    return events;
  }

  static dynamic _decode(String body) {
    try {
      return jsonDecode(body);
    } on FormatException {
      return null;
    }
  }

  static const _unexpected =
      'L\'assistent ha retornat una resposta inesperada.';

  static const _unavailable =
      'L\'assistent no està disponible ara mateix. Torna-ho a provar d\'aquí a una estona.';

  static String _errorMessage(
    http.Response response, {
    required String? code,
    required bool hadSession,
  }) {
    final decoded = _decode(response.body);
    final serverMessage = decoded is Map && decoded['error'] is String
        ? decoded['error'] as String
        : null;
    // Codis d'error del xat (OpenAPI del backend, tasca #143).
    switch (code) {
      case 'CHATBOT_TIMEOUT':
        return 'L\'assistent ha tardat massa a respondre. Torna-ho a provar.';
      case 'EVENTS_UNAVAILABLE':
        return 'Ara mateix no es poden consultar els esdeveniments. Torna-ho a provar d\'aquí a una estona.';
      case 'CHATBOT_UNAVAILABLE':
      case 'CHATBOT_ERROR':
      case 'CHATBOT_INVALID_RESPONSE':
        return _unavailable;
      case 'SESSION_NOT_FOUND':
        return 'Aquesta conversa ja no existeix. Torna a enviar el missatge per començar-ne una de nova.';
    }
    switch (response.statusCode) {
      case 400:
        return serverMessage ?? 'El missatge no és vàlid.';
      case 401:
        return 'La sessió ha caducat. Torna a iniciar sessió.';
      case 404:
        return hadSession
            ? 'Aquesta conversa ja no existeix. Torna a enviar el missatge per començar-ne una de nova.'
            : 'El servidor no té el servei de xat disponible (ruta no trobada).';
      case 429:
        return serverMessage ??
            'Has enviat massa missatges. Espera un minut i torna-ho a provar.';
      case 502:
      case 503:
        return _unavailable;
      case 504:
        return 'L\'assistent ha tardat massa a respondre. Torna-ho a provar.';
      default:
        return 'Error inesperat de l\'assistent (HTTP ${response.statusCode}).';
    }
  }
}
