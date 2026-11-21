import 'package:flutter/material.dart';

import '../../data/chat_filters.dart';
import '../../theme/caliu_colors.dart';

/// Filtres que l'assistent ha entès del missatge, sota la resposta
/// (H.U #12, tasca #138). Així l'usuari veu si l'ha interpretat bé.
class ChatFiltersRow extends StatelessWidget {
  const ChatFiltersRow({super.key, required this.filters, this.now});

  final ChatFilters filters;

  /// Per als tests; per defecte, `DateTime.now()`.
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final labels = filters.labels(now ?? DateTime.now());
    if (labels.isEmpty) return const SizedBox.shrink();
    return Semantics(
      label: 'Filtres interpretats: ${labels.join(', ')}',
      child: ExcludeSemantics(
        child: Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.tune, size: 14, color: CaliuColors.textMuted),
                SizedBox(width: 4),
                Text(
                  'He entès:',
                  style: TextStyle(color: CaliuColors.textMuted, fontSize: 12),
                ),
              ],
            ),
            for (final label in labels)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: CaliuColors.filterBackground,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: CaliuColors.filterBorder),
                ),
                child: Text(
                  label,
                  style: const TextStyle(
                    color: CaliuColors.filterAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
