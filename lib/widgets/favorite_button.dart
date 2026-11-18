import 'package:flutter/material.dart';

import '../data/event.dart';
import '../data/favorites_api.dart';
import '../data/favorites_controller.dart';
import '../theme/caliu_colors.dart';

/// Cor per afegir o treure un esdeveniment dels preferits (tasca #189).
///
/// Canvia a l'instant (estat optimista) i, si la petició falla, torna a
/// l'estat anterior i ho explica amb un SnackBar.
class FavoriteButton extends StatelessWidget {
  const FavoriteButton({
    super.key,
    required this.event,
    this.controller,
    this.color = CaliuColors.textMuted,
    this.activeColor = CaliuColors.red,
    this.size = 24,
  });

  final Event event;

  /// Per defecte, [FavoritesController.shared].
  final FavoritesController? controller;

  /// Color del cor buit.
  final Color color;

  /// Color del cor ple.
  final Color activeColor;
  final double size;

  @override
  Widget build(BuildContext context) {
    final favorites = controller ?? FavoritesController.shared;
    return ListenableBuilder(
      listenable: favorites,
      builder: (context, _) {
        final active = favorites.isFavorite(event.id);
        return IconButton(
          tooltip: active ? 'Treure de preferits' : 'Afegir a preferits',
          onPressed: () => _toggle(context, favorites),
          iconSize: size,
          icon: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            transitionBuilder: (child, animation) =>
                ScaleTransition(scale: animation, child: child),
            child: Icon(
              active ? Icons.favorite : Icons.favorite_border,
              key: ValueKey(active),
              color: active ? activeColor : color,
            ),
          ),
        );
      },
    );
  }

  Future<void> _toggle(
    BuildContext context,
    FavoritesController favorites,
  ) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await favorites.toggle(event);
    } on FavoritesApiException catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger?.showSnackBar(
        const SnackBar(
          content: Text('No s\'han pogut actualitzar els preferits'),
        ),
      );
    }
  }
}
