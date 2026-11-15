import 'package:flutter/material.dart';

import '../data/event.dart';
import '../data/event_when.dart';
import '../theme/caliu_colors.dart';

/// Previsualització ràpida d'un esdeveniment en tocar un marcador del mapa (H.U #44).
///
/// Mostra imatge, categoria, títol, data i lloc. Tocar la targeta o el botó de la
/// fletxa obre la fitxa (`onOpen`). Lliscar avall la nansa la tanca (`onClose`).
class EventPreviewCard extends StatelessWidget {
  const EventPreviewCard({
    super.key,
    required this.event,
    required this.onOpen,
    this.onClose,
    this.now,
  });

  final Event event;
  final VoidCallback onOpen;
  final VoidCallback? onClose;

  /// Per als tests; per defecte, `DateTime.now()`.
  final DateTime? now;

  static const handleKey = Key('event-preview-handle');
  static const openButtonKey = Key('event-preview-open');

  static const _cardColor = Color(0xFF4A1E1E);

  @override
  Widget build(BuildContext context) {
    final category =
        event.categories.isNotEmpty ? event.categories.first : null;
    final place = event.placeLine;

    return Material(
      color: CaliuColors.maroonDeep,
      elevation: 12,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Nansa: zona àmplia perquè sigui fàcil d'arrossegar.
              GestureDetector(
                key: handleKey,
                behavior: HitTestBehavior.opaque,
                onVerticalDragEnd: (details) {
                  if ((details.primaryVelocity ?? 0) > 200) onClose?.call();
                },
                child: SizedBox(
                  width: double.infinity,
                  height: 24,
                  child: Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ),
              Material(
                color: _cardColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: CaliuColors.red.withValues(alpha: 0.6),
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onOpen,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: SizedBox(
                            width: 72,
                            height: 72,
                            child: event.imageUrl != null
                                ? Image.network(
                                    event.imageUrl!,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stack) =>
                                        const _ImagePlaceholder(),
                                  )
                                : const _ImagePlaceholder(),
                          ),
                        ),
                        const SizedBox(width: 12),
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
                                    color: CaliuColors.redSoft,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                              Text(
                                event.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 6),
                              _InfoLine(
                                icon: Icons.calendar_today_outlined,
                                text: previewWhen(event, now ?? DateTime.now()),
                              ),
                              if (place.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                _InfoLine(
                                  icon: Icons.place_outlined,
                                  text: place,
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filled(
                          key: openButtonKey,
                          tooltip: 'Veure fitxa',
                          onPressed: onOpen,
                          style: IconButton.styleFrom(
                            backgroundColor: CaliuColors.red,
                            foregroundColor: Colors.white,
                          ),
                          icon: const Icon(Icons.arrow_forward),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: Colors.white70),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ),
      ],
    );
  }
}

class _ImagePlaceholder extends StatelessWidget {
  const _ImagePlaceholder();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: CaliuColors.maroon,
      child: Icon(Icons.event, color: Colors.white54),
    );
  }
}
