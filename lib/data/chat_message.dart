import 'chat_filters.dart';
import 'chat_plan.dart';
import 'event.dart';

enum ChatRole { user, assistant }

enum ChatMessageStatus { sent, failed }

/// Un missatge del xat (H.U #11). Immutable: el controlador en crea còpies.
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.role,
    required this.text,
    this.events = const [],
    this.filters,
    this.plan,
    this.status = ChatMessageStatus.sent,
    this.retryOf,
  });

  final String id;
  final ChatRole role;
  final String text;

  /// Targetes d'esdeveniment a mostrar sota la resposta (tasca #134).
  final List<Event> events;

  /// Filtres interpretats a mostrar sota la resposta (tasca #138).
  final ChatFilters? filters;

  /// Itinerari a mostrar amb el widget de passos (tasca #141).
  final ChatPlan? plan;
  final ChatMessageStatus status;

  /// Resposta alternativa (tasca #144): l'assistent no ha pogut respondre i
  /// el backend ha enviat un text fix. Guarda l'id del missatge de l'usuari
  /// que es pot tornar a enviar; null en una resposta normal.
  final String? retryOf;

  bool get isFallback => retryOf != null;

  bool get isUser => role == ChatRole.user;
  bool get failed => status == ChatMessageStatus.failed;

  ChatMessage copyWith({ChatMessageStatus? status}) => ChatMessage(
    id: id,
    role: role,
    text: text,
    events: events,
    filters: filters,
    plan: plan,
    status: status ?? this.status,
    retryOf: retryOf,
  );
}
