import 'package:flutter/foundation.dart';

import 'auth_session.dart';
import 'chat_api.dart';
import 'chat_demo.dart';
import 'chat_locale.dart';
import 'chat_message.dart';

/// Estat del xat, separat de la UI (H.U #11).
///
/// La pantalla només llegeix aquest estat i crida [send], [retry],
/// [startNewConversation], [openSession]...
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

  /// S'està carregant una conversa desada: l'última en entrar al xat o una
  /// de l'historial (tasca #164). No bloqueja l'input: si l'usuari escriu
  /// abans que acabi, la càrrega es descarta.
  bool loadingConversation = false;

  /// S'està creant una conversa nova (tasca #162).
  bool creatingSession = false;

  int _nextId = 0;
  bool _disposed = false;

  /// Token amb què s'ha recuperat l'última conversa. Si canvia (s'ha tornat
  /// a iniciar sessió, potser amb un altre compte), es torna a recuperar.
  String? _restoredFor;

  /// Comptador de càrregues: una càrrega només s'aplica si encara és l'última
  /// (un enviament, una conversa nova o una altra càrrega la invaliden).
  int _loadId = 0;

  Future<void> checkSession() async {
    checkingSession = true;
    _notify();
    final token = await _session.readToken();
    if (_disposed) return;
    needsLogin = token == null || token.isEmpty;
    checkingSession = false;
    _notify();
    if (!needsLogin && token != _restoredFor) await _restoreLast(token!);
  }

  /// En entrar al xat es conserva la conversa immediatament anterior
  /// (H.U #48): es reobre la sessió més recent de l'historial. Si falla, es
  /// comença una conversa nova sense mostrar cap error.
  Future<void> _restoreLast(String token) async {
    final changedAccount = _restoredFor != null;
    _restoredFor = token;
    if (changedAccount) {
      // Els missatges en memòria poden ser d'un altre compte.
      _messages.clear();
      sessionId = null;
      error = null;
    } else if (_messages.isNotEmpty || sessionId != null) {
      return;
    }
    final load = _startLoading();
    try {
      final sessions = await _api.listSessions(token: token);
      if (!_isCurrent(load)) return;
      final last = sessions.firstOrNull;
      if (last == null) return;
      final messages = last.isEmpty
          ? const <ChatMessage>[]
          : await _api.fetchMessages(token: token, sessionId: last.id);
      if (!_isCurrent(load)) return;
      sessionId = last.id;
      _messages.addAll(messages);
    } on ChatApiException catch (e) {
      if (_isCurrent(load) && e.isUnauthorized) await _expire(token);
    } finally {
      _finishLoading(load);
    }
  }

  /// Reobre una conversa de l'historial (tasca #164). Retorna false si no
  /// s'ha pogut obrir (l'error queda a [error]).
  Future<bool> openSession(String id) async {
    if (isTyping || creatingSession) return false;
    // Ja és la conversa oberta: es conserven les targetes i els itineraris,
    // que el backend no desa.
    if (id == sessionId && !loadingConversation) return true;
    final token = await _session.readToken();
    if (_disposed) return false;
    if (token == null || token.isEmpty) {
      needsLogin = true;
      _notify();
      return false;
    }
    error = null;
    final load = _startLoading();
    try {
      final messages = await _api.fetchMessages(token: token, sessionId: id);
      if (!_isCurrent(load)) return false;
      _messages
        ..clear()
        ..addAll(messages);
      sessionId = id;
      return true;
    } on ChatApiException catch (e) {
      if (!_isCurrent(load)) return false;
      if (e.isUnauthorized) await _expire(token);
      error = e.isSessionLost ? 'Aquesta conversa ja no existeix.' : e.message;
      return false;
    } finally {
      _finishLoading(load);
    }
  }

  /// Historial de converses per a la pantalla d'historial (tasca #164).
  /// Llança [ChatApiException] si no es pot carregar.
  Future<List<ChatSessionSummary>> loadSessions() async {
    final token = await _session.readToken();
    if (token == null || token.isEmpty) {
      throw const ChatApiException(
        'La sessió ha caducat. Torna a iniciar sessió.',
        statusCode: 401,
      );
    }
    try {
      return await _api.listSessions(token: token);
    } on ChatApiException catch (e) {
      if (e.isUnauthorized && !_disposed) {
        await _expire(token);
        _notify();
      }
      rethrow;
    }
  }

  /// "Nova conversa" (tasca #162, H.U #47): crea una sessió nova al backend i
  /// buida la pantalla. Les respostes de la sessió nova no tenen el context
  /// de l'anterior, que es conserva a l'historial.
  Future<void> startNewConversation() async {
    if (isTyping || creatingSession) return;
    // Ja és una conversa buida: no cal crear-ne una altra.
    if (_messages.isEmpty && !loadingConversation) return;
    final token = await _session.readToken();
    if (_disposed) return;
    if (token == null || token.isEmpty) {
      needsLogin = true;
      _notify();
      return;
    }
    _cancelLoading();
    creatingSession = true;
    error = null;
    _notify();
    try {
      final id = await _api.createSession(token: token);
      if (_disposed) return;
      _clearConversation();
      sessionId = id;
    } on ChatApiException catch (e) {
      if (_disposed) return;
      if (e.isUnauthorized) {
        await _expire(token);
        error = e.message;
      } else {
        // Sense sessió, el backend en crea una de nova (també sense context)
        // amb el primer missatge: la conversa nova funciona igualment.
        _clearConversation();
      }
    } finally {
      creatingSession = false;
      _notify();
    }
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

  /// Buida el xat en local, sense crear cap sessió al backend (el primer
  /// missatge en crearà una). Per a una conversa nova, [startNewConversation].
  void reset() {
    _cancelLoading();
    _clearConversation();
    isTyping = false;
    _notify();
  }

  void _clearConversation() {
    _messages.clear();
    sessionId = null;
    error = null;
  }

  int _startLoading() {
    loadingConversation = true;
    _notify();
    return ++_loadId;
  }

  bool _isCurrent(int load) => !_disposed && load == _loadId;

  void _finishLoading(int load) {
    if (!_isCurrent(load)) return;
    loadingConversation = false;
    _notify();
  }

  void _cancelLoading() {
    _loadId++;
    loadingConversation = false;
  }

  /// Token caducat: cal tornar a iniciar sessió. Només s'esborra el token si
  /// és el mateix que ha fallat.
  Future<void> _expire(String token) async {
    needsLogin = true;
    if (await _session.readToken() == token) await _session.clear();
  }

  void dismissError() {
    if (error == null) return;
    error = null;
    _notify();
  }

  Future<void> _request(ChatMessage message) async {
    // Escriure abans que acabi de carregar una conversa la descarta.
    _cancelLoading();
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
        await _expire(token);
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
