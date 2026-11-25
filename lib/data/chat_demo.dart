import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'auth_session.dart';
import 'chat_api.dart';
import 'chat_filters.dart';
import 'chat_message.dart';
import 'chat_plan.dart';
import 'event.dart';

/// Mode demo del xat: respostes d'exemple sense backend ni Gemini, per veure
/// les targetes (#134), els filtres (#138) i l'itinerari (#141) en local o
/// fer una demo sense dependre de la quota.
///
/// S'activa amb `--dart-define=CHAT_DEMO=true`
/// (`.\scripts\run-web.ps1 -ChatDemo`). Per defecte està apagat.
const chatDemoMode = bool.fromEnvironment('CHAT_DEMO');

/// Sessió sempre iniciada per al mode demo (no cal fer login).
class DemoChatSession implements AuthSessionStore {
  @override
  Future<String?> readToken() async => 'demo';

  @override
  Future<void> saveToken(String token) async {}

  @override
  Future<void> clear() async {}
}

/// Respostes d'exemple (també «prova error» i «prova timeout», tasca #144). Si el missatge demana un itinerari, una ruta o
/// "un pla", retorna un itinerari; si no, una resposta amb filtres i targetes.
/// Els esdeveniments són inventats: la fitxa mostrarà les dades de la targeta
/// però no les trobarà al backend.
class DemoChatApi extends ChatApi {
  DemoChatApi({this.latency = const Duration(milliseconds: 900)});

  final Duration latency;

  /// Missatges de prova d'errors (#144) que ja han fallat una vegada: en
  /// reintentar-los, responen bé.
  final Set<String> _failedOnce = {};

  /// Converses en memòria per provar "Nova conversa" (#162) i l'historial
  /// (#164). Es perden en tancar l'app.
  final List<_DemoSession> _sessions = [];
  int _nextSession = 0;
  int _nextMessage = 0;

  _DemoSession _newSession() {
    final session = _DemoSession('demo-${++_nextSession}');
    _sessions.insert(0, session);
    return session;
  }

  @override
  Future<String> createSession({required String token}) async =>
      _newSession().id;

  @override
  Future<List<ChatSessionSummary>> listSessions({
    required String token,
  }) async => [
    for (final session in _sessions)
      ChatSessionSummary(
        id: session.id,
        title: session.messages.firstOrNull?.text,
        lastActivityAt: session.lastActivityAt,
      ),
  ];

  @override
  Future<List<ChatMessage>> fetchMessages({
    required String token,
    required String sessionId,
  }) async {
    final session = _sessions.where((s) => s.id == sessionId).firstOrNull;
    if (session == null) {
      throw const ChatApiException(
        'Aquesta conversa ja no existeix.',
        statusCode: 404,
        code: 'SESSION_NOT_FOUND',
        sessionLost: true,
      );
    }
    return List.of(session.messages);
  }

  @override
  Future<ChatReply> sendMessage({
    required String token,
    required String message,
    String? sessionId,
    String? locale,
  }) async {
    final reply = await _reply(message);
    // Com el backend: una resposta alternativa no es desa ni crea sessió.
    if (reply.isFallback) return reply;
    final session =
        _sessions.where((s) => s.id == sessionId).firstOrNull ?? _newSession();
    session.messages.addAll([
      ChatMessage(
        id: 'hd${_nextMessage++}',
        role: ChatRole.user,
        text: message.trim(),
      ),
      ChatMessage(
        id: 'hd${_nextMessage++}',
        role: ChatRole.assistant,
        text: reply.reply,
      ),
    ]);
    session.lastActivityAt = DateTime.now();
    _sessions
      ..remove(session)
      ..insert(0, session);
    return ChatReply(
      sessionId: session.id,
      reply: reply.reply,
      events: reply.events,
      filters: reply.filters,
      plan: reply.plan,
    );
  }

  Future<ChatReply> _reply(String message) async {
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    final text = message.toLowerCase();
    // Prova dels errors (#144): «prova error» dona una resposta alternativa i
    // «prova timeout» un error; en tornar-ho a provar, responen bé.
    if (text.contains('prova error') && _failedOnce.add(text)) {
      return const ChatReply(
        sessionId: null,
        isFallback: true,
        reply:
            'Ara mateix no puc respondre del tot. Mentrestant, aquí tens '
            'algunes activitats d\'avui. Torna a enviar el missatge d\'aquí a '
            'una estona.',
      );
    }
    if (text.contains('prova timeout') && _failedOnce.add(text)) {
      throw const ChatApiException(
        'L\'assistent ha tardat massa a respondre. Torna-ho a provar.',
        statusCode: 504,
        code: 'CHATBOT_TIMEOUT',
      );
    }
    final wantsPlan = [
      'itinerari',
      'itinerario',
      'itinerary',
      'ruta',
      'un pla',
    ].any(text.contains);
    return wantsPlan ? _planReply() : _textReply();
  }

  static DateTime _today(int hour, [int minute = 0]) {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, hour, minute);
  }

  static ChatReply _textReply() {
    final events = [
      Event(
        id: 'demo-1',
        title: 'Concert de jazz al Born',
        venue: 'Born Centre de Cultura',
        municipality: 'Barcelona',
        startDate: _today(19, 30),
        categories: const ['Música'],
        price: 0,
        location: const LatLng(41.3856, 2.1834),
      ),
      Event(
        id: 'demo-2',
        title: 'Taller de titelles per a famílies',
        venue: 'Biblioteca Jaume Fuster',
        municipality: 'Barcelona',
        startDate: _today(17),
        categories: const ['Tallers'],
        price: 0,
        location: const LatLng(41.4082, 2.1510),
      ),
    ];
    return ChatReply(
      sessionId: 'demo',
      reply:
          'Avui a la tarda a Barcelona tens dues opcions gratuïtes:\n'
          '• Concert de jazz al Born, a les 19:30 al Born Centre de Cultura.\n'
          '• Taller de titelles per a famílies, a les 17:00 a la Biblioteca '
          'Jaume Fuster.',
      events: events,
      filters: ChatFilters(
        from: _today(15),
        to: _today(20),
        timeOfDay: 'tarda',
        maxPrice: 0,
        municipality: 'Barcelona',
      ),
    );
  }

  static ChatReply _planReply() {
    final steps = [
      ChatPlanStep(
        order: 1,
        id: 'demo-3',
        title: 'Visita guiada al Call jueu',
        start: _today(10, 30),
        end: _today(12),
        venue: 'Call jueu',
        municipality: 'Girona',
        location: const LatLng(41.9875, 2.8259),
      ),
      ChatPlanStep(
        order: 2,
        id: 'demo-4',
        title: 'Concert vermut a la plaça',
        start: _today(12, 30),
        end: _today(13, 30),
        venue: 'Plaça de la Independència',
        municipality: 'Girona',
        location: const LatLng(41.9845, 2.8240),
        distanceKm: 0.4,
        travelMinutes: 5,
      ),
      ChatPlanStep(
        order: 3,
        id: 'demo-5',
        title: 'Exposició: Girona medieval',
        start: _today(16),
        end: _today(17, 30),
        venue: 'Museu d\'Història de Girona',
        municipality: 'Girona',
        location: const LatLng(41.9871, 2.8262),
        distanceKm: 1.2,
        travelMinutes: 15,
      ),
    ];
    final now = DateTime.now();
    return ChatReply(
      sessionId: 'demo',
      reply:
          'Aquí tens un itinerari de 3 passos per avui a Girona:\n'
          '1. 10:30–12:00 · Visita guiada al Call jueu\n'
          '2. 12:30–13:30 · Concert vermut a la plaça\n'
          '3. 16:00–17:30 · Exposició: Girona medieval',
      plan: ChatPlan(
        date: DateTime(now.year, now.month, now.day),
        steps: steps,
      ),
      filters: ChatFilters(
        from: _today(10),
        to: _today(23, 59),
        municipality: 'Girona',
      ),
    );
  }
}

class _DemoSession {
  _DemoSession(this.id);

  final String id;
  final List<ChatMessage> messages = [];
  DateTime lastActivityAt = DateTime.now();
}
