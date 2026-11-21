import 'package:flutter/material.dart';

import '../../data/chat_message.dart';
import '../../data/event.dart';
import '../../theme/caliu_colors.dart';
import 'chat_event_card.dart';
import 'chat_filters_row.dart';
import 'chat_itinerary_card.dart';

/// Bombolla d'un missatge. Les respostes de l'assistent poden portar a sota
/// els filtres interpretats (tasca #138), un itinerari (tasca #141) i
/// targetes d'esdeveniment (tasca #134).
class ChatBubble extends StatelessWidget {
  const ChatBubble({
    super.key,
    required this.message,
    required this.onOpenEvent,
    this.onRetry,
    this.onOpenRoute,
    this.now,
  });

  final ChatMessage message;
  final ValueChanged<Event> onOpenEvent;
  final VoidCallback? onRetry;

  /// Com obrir la ruta d'un itinerari. Per defecte, Google Maps.
  final Future<void> Function(Uri uri)? onOpenRoute;
  final DateTime? now;

  /// Amb itinerari, el widget ja mostra els passos: de la resposta només
  /// es mostra la introducció (la primera línia).
  String get _text {
    if (message.plan == null) return message.text;
    final intro = message.text.split('\n').first.trim();
    return intro.isEmpty ? message.text : intro;
  }

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
        _text,
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
          if (message.filters case final filters? when !isUser)
            Padding(
              padding: const EdgeInsets.only(top: 6, right: 24),
              child: ChatFiltersRow(
                key: ValueKey('chat-filters-${message.id}'),
                filters: filters,
                now: now,
              ),
            ),
          if (message.plan case final plan? when !isUser)
            Padding(
              padding: const EdgeInsets.only(top: 6, right: 24),
              child: ChatItineraryCard(
                key: ValueKey('chat-plan-${message.id}'),
                plan: plan,
                now: now,
                onOpenRoute: onOpenRoute,
                onOpenStep: (step) => onOpenEvent(step.toEvent()),
              ),
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
