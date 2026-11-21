import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';
import 'event.dart';

class ChatApiException implements Exception {
  const ChatApiException(
    this.message, {
    this.statusCode,
    this.sessionLost = false,
  });

  final String message;
  final int? statusCode;

  /// Token caducat o invàlid: cal tornar a iniciar sessió.
  bool get isUnauthorized => statusCode == 401;

  /// La sessió de xat ja no existeix: cal començar-ne una de nova.
  /// Només és cert si s'havia enviat un `sessionId` (un 404 sense sessió vol
  /// dir que el servidor no té la ruta del xat).
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
  });

  final String sessionId;
  final String reply;

  /// Esdeveniments que esmenta la resposta (H.U #11, tasca #134).
  /// Camp opcional: si el backend no l'envia, la llista és buida.
  final List<Event> events;
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

  Future<ChatReply> sendMessage({
    required String token,
    required String message,
    String? sessionId,
  }) async {
    final uri = Uri.parse('$_baseUrl/chat/messages');
    late final http.Response response;
    try {
      response = await _client
          .post(
            uri,
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'message': message, 'sessionId': ?sessionId}),
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

    if (response.statusCode != 200) {
      final sessionLost = response.statusCode == 404 && sessionId != null;
      throw ChatApiException(
        _errorMessage(response, hadSession: sessionId != null),
        statusCode: response.statusCode,
        sessionLost: sessionLost,
      );
    }

    final decoded = _decode(response.body);
    final reply = decoded is Map<String, dynamic> ? decoded['reply'] : null;
    final newSessionId = decoded is Map<String, dynamic>
        ? decoded['sessionId']
        : null;
    if (reply is! String || reply.trim().isEmpty || newSessionId is! String) {
      throw const ChatApiException(
        'L\'assistent ha retornat una resposta inesperada.',
      );
    }
    return ChatReply(
      sessionId: newSessionId,
      reply: reply.trim(),
      events: _parseEvents((decoded as Map<String, dynamic>)['events']),
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

  static String _errorMessage(
    http.Response response, {
    required bool hadSession,
  }) {
    final decoded = _decode(response.body);
    final serverMessage = decoded is Map && decoded['error'] is String
        ? decoded['error'] as String
        : null;
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
        return 'L\'assistent no està disponible ara mateix. Torna-ho a provar d\'aquí a una estona.';
      default:
        return 'Error inesperat de l\'assistent (HTTP ${response.statusCode}).';
    }
  }
}
