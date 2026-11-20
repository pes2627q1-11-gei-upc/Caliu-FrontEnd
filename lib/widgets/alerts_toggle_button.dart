import 'package:flutter/material.dart';

import '../data/event.dart';
import '../data/favorite_alerts_controller.dart';
import '../data/favorites_api.dart';
import '../data/favorites_controller.dart';
import '../theme/caliu_colors.dart';

/// Avís que les notificacions encara no s'envien (no hi ha FCM integrat):
/// de moment només es desa la preferència, per quan existeixin.
const alertsComingSoonNote =
    'Les notificacions arribaran properament: de moment es desa la teva '
    'preferència.';

/// Campana per silenciar o activar les alertes d'un esdeveniment guardat
/// (tasca #171, H.U #52). Només es mostra si l'esdeveniment és als
/// preferits; silenciar-lo no el treu dels preferits.
class AlertsToggleButton extends StatelessWidget {
  const AlertsToggleButton({
    super.key,
    required this.event,
    this.alerts,
    this.favorites,
    this.color = CaliuColors.textMuted,
    this.activeColor = CaliuColors.maroon,
    this.size = 24,
  });

  final Event event;

  /// Per defecte, [FavoriteAlertsController.shared].
  final FavoriteAlertsController? alerts;

  /// Per defecte, [FavoritesController.shared].
  final FavoritesController? favorites;

  /// Color de la campana silenciada.
  final Color color;

  /// Color de la campana amb les alertes actives.
  final Color activeColor;
  final double size;

  @override
  Widget build(BuildContext context) {
    final alerts = this.alerts ?? FavoriteAlertsController.shared;
    final favorites = this.favorites ?? FavoritesController.shared;
    return ListenableBuilder(
      listenable: Listenable.merge([alerts, favorites]),
      builder: (context, _) {
        if (!favorites.isFavorite(event.id)) return const SizedBox.shrink();
        final enabled = alerts.alertsEnabled(event.id);
        return IconButton(
          tooltip: enabled ? 'Silenciar alertes' : 'Activar alertes',
          iconSize: size,
          onPressed: () => _toggle(context, alerts),
          icon: Icon(
            enabled
                ? Icons.notifications_active_outlined
                : Icons.notifications_off_outlined,
            color: enabled ? activeColor : color,
          ),
        );
      },
    );
  }

  Future<void> _toggle(
    BuildContext context,
    FavoriteAlertsController alerts,
  ) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final willEnable = !alerts.alertsEnabled(event.id);
    try {
      final pending = alerts.toggle(event.id);
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  willEnable
                      ? 'Alertes activades per a "${event.title}"'
                      : 'Alertes silenciades per a "${event.title}"',
                ),
                const SizedBox(height: 4),
                const Text(
                  alertsComingSoonNote,
                  style: TextStyle(fontSize: 12, color: Colors.white70),
                ),
              ],
            ),
          ),
        );
      await pending;
    } on FavoritesApiException catch (e) {
      _showError(messenger, e.message);
    } catch (_) {
      _showError(messenger, 'No s\'han pogut actualitzar les alertes');
    }
  }

  /// L'error substitueix l'avís optimista en lloc de quedar a la cua.
  void _showError(ScaffoldMessengerState? messenger, String message) {
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
