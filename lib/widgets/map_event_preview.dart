import 'package:flutter/material.dart';

import '../data/event.dart';
import 'event_preview_card.dart';

/// Previsualització animada del marcador seleccionat al mapa (H.U #44).
///
/// També gestiona el botó enrere: si hi ha una targeta oberta, el primer "enrere"
/// la tanca en lloc de sortir. Només ho fa si [active] és cert (pestanya Mapa
/// visible): el mapa continua muntat dins de l'`IndexedStack` de `MainScreen`.
class MapEventPreview extends StatelessWidget {
  const MapEventPreview({
    super.key,
    required this.selected,
    required this.onOpen,
    required this.onClose,
    this.active = true,
    this.now,
  });

  final Event? selected;
  final ValueChanged<Event> onOpen;
  final VoidCallback onClose;
  final bool active;

  /// Per als tests; per defecte, `DateTime.now()`.
  final DateTime? now;

  static const animationDuration = Duration(milliseconds: 220);

  @override
  Widget build(BuildContext context) {
    final event = selected;
    return PopScope(
      canPop: event == null || !active,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) onClose();
      },
      child: AnimatedSwitcher(
        duration: animationDuration,
        transitionBuilder: (child, animation) => SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
        child: event == null
            ? const SizedBox.shrink(key: ValueKey('none'))
            : EventPreviewCard(
                key: ValueKey(event.id),
                event: event,
                // Cada targeta captura el seu esdeveniment: mentre desapareix,
                // `selected` ja és null però la targeta encara es pot tocar.
                onOpen: () => onOpen(event),
                onClose: onClose,
                now: now,
              ),
      ),
    );
  }
}
