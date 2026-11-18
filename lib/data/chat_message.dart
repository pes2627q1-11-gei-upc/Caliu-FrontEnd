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
    this.status = ChatMessageStatus.sent,
  });

  final String id;
  final ChatRole role;
  final String text;

  /// Targetes d'esdeveniment a mostrar sota la resposta (tasca #134).
  final List<Event> events;
  final ChatMessageStatus status;

  bool get isUser => role == ChatRole.user;
  bool get failed => status == ChatMessageStatus.failed;

  ChatMessage copyWith({ChatMessageStatus? status}) => ChatMessage(
    id: id,
    role: role,
    text: text,
    events: events,
    status: status ?? this.status,
  );
}
