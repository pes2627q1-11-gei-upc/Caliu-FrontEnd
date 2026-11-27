import 'package:flutter/material.dart';

import '../../data/event.dart';
import '../../data/event_when.dart';
import '../../theme/caliu_colors.dart';

/// Targeta clicable d'un esdeveniment dins del xat (tasca #134).
class ChatEventCard extends StatelessWidget {
  const ChatEventCard({
    super.key,
    required this.event,
    required this.onTap,
    this.now,
  });

  final Event event;
  final VoidCallback onTap;

  /// Per als tests; per defecte, `DateTime.now()`.
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final category = event.categories.isNotEmpty
        ? event.categories.first
        : null;
    final details = [
      previewWhen(event, now ?? DateTime.now()),
      if (event.shortPlace.isNotEmpty) event.shortPlace,
    ].join(' · ');

    return Semantics(
      button: true,
      label: 'Veure fitxa de ${event.title}',
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: CaliuColors.red.withValues(alpha: 0.25)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 56,
                    height: 56,
                    child: event.imageUrl != null
                        ? Image.network(
                            event.imageUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stack) =>
                                const _Placeholder(),
                          )
                        : const _Placeholder(),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (category != null)
                        Text(
                          category.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: CaliuColors.red,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                          ),
                        ),
                      Text(
                        event.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: CaliuColors.maroonDeep,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        details,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: CaliuColors.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: CaliuColors.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: CaliuColors.maroon,
      child: Icon(Icons.event, color: Colors.white54),
    );
  }
}
