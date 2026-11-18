import 'package:flutter/material.dart';

import '../data/event.dart';
import '../theme/caliu_colors.dart';
import 'caliu_chip.dart';

/// Targeta d'esdeveniment per a llistes (cerca, preferits…).
class EventListTile extends StatelessWidget {
  const EventListTile({
    super.key,
    required this.event,
    required this.subtitle,
    required this.onTap,
    this.trailing,
  });

  final Event event;
  final String subtitle;
  final VoidCallback onTap;

  /// Widget a la dreta (p. ex. el cor de preferits).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final labels = <String>{...event.categories, ...event.tags}.take(3);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: CaliuColors.maroon.withValues(alpha: 0.14)),
        boxShadow: [
          BoxShadow(
            color: CaliuColors.maroonDeep.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 64,
                    height: 64,
                    child: event.imageUrl != null
                        ? Image.network(
                            event.imageUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                const _ThumbPlaceholder(),
                          )
                        : const _ThumbPlaceholder(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        event.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: CaliuColors.maroonDeep,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: CaliuColors.textMuted,
                          fontSize: 13,
                        ),
                      ),
                      if (labels.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: labels
                                .map((label) => CaliuChip(label: label))
                                .toList(),
                          ),
                        ),
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ThumbPlaceholder extends StatelessWidget {
  const _ThumbPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: CaliuColors.maroon,
      child: Icon(Icons.event, color: Colors.white54),
    );
  }
}
