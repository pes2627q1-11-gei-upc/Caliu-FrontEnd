import 'package:flutter/material.dart';

import '../../data/chat_message.dart';
import '../../data/event.dart';
import '../../theme/caliu_colors.dart';
import 'chat_event_card.dart';

/// Bombolla d'un missatge. Les respostes de l'assistent poden portar targetes
/// d'esdeveniment a sota (tasca #134).
class ChatBubble extends StatelessWidget {
  const ChatBubble({
    super.key,
    required this.message,
    required this.onOpenEvent,
    this.onRetry,
    this.now,
  });

  final ChatMessage message;
  final ValueChanged<Event> onOpenEvent;
  final VoidCallback? onRetry;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    final bubble = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isUser ? CaliuColors.maroon : Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: Radius.circular(isUser ? 18 : 4),
          bottomRight: Radius.circular(isUser ? 4 : 18),
        ),
        border: message.failed
            ? Border.all(color: CaliuColors.red, width: 1.5)
            : isUser
            ? null
            : Border.all(color: CaliuColors.maroon.withValues(alpha: 0.1)),
      ),
      child: SelectableText(
        message.text,
        style: TextStyle(
          color: isUser ? Colors.white : CaliuColors.maroonDeep,
          fontSize: 15,
          height: 1.35,
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: isUser
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * 0.8,
            ),
            child: bubble,
          ),
          if (message.failed)
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('No enviat · Tornar a provar'),
              style: TextButton.styleFrom(foregroundColor: CaliuColors.red),
            ),
          for (final event in message.events)
            Padding(
              padding: const EdgeInsets.only(top: 6, right: 24),
              child: ChatEventCard(
                key: ValueKey('chat-event-${message.id}-${event.id}'),
                event: event,
                now: now,
                onTap: () => onOpenEvent(event),
              ),
            ),
        ],
      ),
    );
  }
}
