import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';
import 'chat_filters.dart';
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
    final response = await _post(
      token: token,
      message: message,
      sessionId: sessionId,
      locale: locale,
    );

    if (response.statusCode != 200) {
      final error = _decode(response.body);
      final code = error is Map && error['code'] is String
          ? error['code'] as String
          : null;
      final sessionLost =
          code == 'SESSION_NOT_FOUND' ||
          (code == null && response.statusCode == 404 && sessionId != null);
      throw ChatApiException(
        _errorMessage(response, code: code, hadSession: sessionId != null),
        statusCode: response.statusCode,
        code: code,
        sessionLost: sessionLost,
      );
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
      throw const ChatApiException(
        'L\'assistent ha retornat una resposta inesperada.',
      );
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

  Future<http.Response> _post({
    required String token,
    required String message,
    String? sessionId,
    String? locale,
  }) async {
    final uri = Uri.parse('$_baseUrl/chat/messages');
    try {
      return await _client
          .post(
            uri,
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'message': message,
              'sessionId': ?sessionId,
              'locale': ?locale,
            }),
          )
          .timeout(timeout);
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
