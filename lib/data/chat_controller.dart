import 'package:flutter/foundation.dart';

import 'auth_session.dart';
import 'chat_api.dart';
import 'chat_demo.dart';
import 'chat_locale.dart';
import 'chat_message.dart';

/// Estat del xat, separat de la UI (H.U #11).
///
/// La pantalla només llegeix aquest estat i crida [send], [retry], [reset]...
/// Així la lògica es pot testejar sense widgets.
class ChatController extends ChangeNotifier {
  ChatController({
    ChatApi? api,
    AuthSessionStore? session,
    String Function()? locale,
  }) : _api = api ?? (chatDemoMode ? DemoChatApi() : ChatApi()),
       _session = session ?? (chatDemoMode ? DemoChatSession() : AuthSession()),
       _locale = locale ?? appChatLocale;

  final ChatApi _api;
  final AuthSessionStore _session;

  /// Idioma de l'app que s'envia amb cada missatge (tasca #147).
  final String Function() _locale;

  final List<ChatMessage> _messages = [];
  List<ChatMessage> get messages => List.unmodifiable(_messages);

  /// L'assistent està processant la resposta (indicador "escrivint...").
  bool isTyping = false;

  /// Encara no sabem si hi ha sessió iniciada.
  bool checkingSession = true;

  /// No hi ha token (o ha caducat): el xat demana iniciar sessió.
  bool needsLogin = false;

  /// Últim error a mostrar (es pot tancar amb [dismissError]).
  String? error;

  /// Sessió de xat del backend; es reutilitza perquè l'assistent tingui context.
  String? sessionId;

  int _nextId = 0;
  bool _disposed = false;

  Future<void> checkSession() async {
    checkingSession = true;
    _notify();
    final token = await _session.readToken();
    if (_disposed) return;
    needsLogin = token == null || token.isEmpty;
    checkingSession = false;
    _notify();
  }

  /// Envia un missatge nou. Ignora textos buits o enviaments simultanis.
  Future<void> send(String rawText) async {
    final text = rawText.trim();
    if (text.isEmpty || isTyping) return;
    if (text.length > ChatApi.maxMessageLength) {
      error =
          'El missatge és massa llarg (màxim ${ChatApi.maxMessageLength} caràcters).';
      _notify();
      return;
    }
    final message = ChatMessage(
      id: 'u${_nextId++}',
      role: ChatRole.user,
      text: text,
    );
    _messages.add(message);
    await _request(message);
  }

  /// Torna a enviar un missatge que ha fallat.
  Future<void> retry(String messageId) async {
    if (isTyping) return;
    final index = _messages.indexWhere(
      (m) => m.id == messageId && m.isUser && m.failed,
    );
    if (index == -1) return;
    final message = _messages[index].copyWith(status: ChatMessageStatus.sent);
    _messages[index] = message;
    await _request(message);
  }

  /// Torna a enviar el missatge d'una resposta alternativa (tasca #144):
  /// treu la resposta alternativa i repeteix la pregunta. El backend no l'ha
  /// desat a l'historial, així que no queda duplicada.
  Future<void> retryFallback(String fallbackId) async {
    if (isTyping) return;
    final index = _messages.indexWhere(
      (m) => m.id == fallbackId && m.isFallback,
    );
    if (index == -1) return;
    final questionId = _messages[index].retryOf;
    final question = _messages.where((m) => m.id == questionId).firstOrNull;
    if (question == null) return;
    _messages.removeAt(index);
    await _request(question);
  }

  /// Comença una conversa nova (base per a la H.U #47).
  void reset() {
    _messages.clear();
    sessionId = null;
    error = null;
    isTyping = false;
    _notify();
  }

  void dismissError() {
    if (error == null) return;
    error = null;
    _notify();
  }

  Future<void> _request(ChatMessage message) async {
    error = null;
    isTyping = true;
    _notify();

    final token = await _session.readToken();
    if (_disposed) return;
    if (token == null || token.isEmpty) {
      needsLogin = true;
      _markFailed(message.id);
      isTyping = false;
      _notify();
      return;
    }

    try {
      final reply = await _api.sendMessage(
        token: token,
        message: message.text,
        sessionId: sessionId,
        locale: _locale(),
      );
      if (_disposed) return;
      // Una resposta alternativa d'una conversa nova no porta sessió.
      sessionId = reply.sessionId ?? sessionId;
      _messages.add(
        ChatMessage(
          id: 'a${_nextId++}',
          role: ChatRole.assistant,
          text: reply.reply,
          events: reply.events,
          filters: reply.filters,
          plan: reply.plan,
          retryOf: reply.isFallback ? message.id : null,
        ),
      );
    } on ChatApiException catch (e) {
      if (_disposed) return;
      if (e.isSessionLost) sessionId = null;
      if (e.isUnauthorized) {
        needsLogin = true;
        // Només esborrem el token si és el mateix que ha fallat.
        if (await _session.readToken() == token) await _session.clear();
        if (_disposed) return;
      }
      _markFailed(message.id);
      error = e.message;
    }
    isTyping = false;
    _notify();
  }

  void _markFailed(String messageId) {
    final index = _messages.indexWhere((m) => m.id == messageId);
    if (index != -1) {
      _messages[index] = _messages[index].copyWith(
        status: ChatMessageStatus.failed,
      );
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
