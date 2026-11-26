import 'package:flutter/material.dart';

import '../data/event.dart';
import '../data/favorites_api.dart';
import '../data/favorites_controller.dart';
import '../theme/caliu_colors.dart';
import 'favorites_login_prompt.dart';

/// Botó per afegir o treure un esdeveniment dels preferits (tasca #189).
///
/// Canvia a l'instant (estat optimista) i, si la petició falla, torna a
/// l'estat anterior i ho explica amb un SnackBar. Sense sessió, demana
/// iniciar-la i, si l'usuari ho fa, completa l'acció (tasca #191).
class FavoriteButton extends StatelessWidget {
  const FavoriteButton({
    super.key,
    required this.event,
    this.controller,
    this.color = CaliuColors.textMuted,
    this.activeColor = CaliuColors.red,
    this.size = 24,
    this.loginBuilder,
    this.onRemoved,
    this.showBookmark = false,
  });

  final Event event;

  /// Per defecte, [FavoritesController.shared].
  final FavoritesController? controller;

  /// Color del cor buit.
  final Color color;

  /// Color del cor ple.
  final Color activeColor;
  final double size;

  /// Per als tests; per defecte, la pantalla de login de l'app.
  final FavoritesLoginBuilder? loginBuilder;

  /// Es crida quan l'usuari treu l'esdeveniment dels preferits, just després
  /// del canvi optimista (p. ex. per oferir "Desfer", tasca #167).
  final VoidCallback? onRemoved;

  /// Mostra el botó amb etiqueta «Desar» / «Desat» (cor) a la barra de la fitxa.
  final bool showBookmark;

  @override
  Widget build(BuildContext context) {
    final favorites = controller ?? FavoritesController.shared;
    return ListenableBuilder(
      listenable: favorites,
      builder: (context, _) {
        final active = favorites.isFavorite(event.id);
        Future<void> onPressed() => _onPressed(context, favorites);
        if (showBookmark) {
          return OutlinedButton.icon(
            onPressed: onPressed,
            icon: Icon(active ? Icons.favorite : Icons.favorite_border),
            label: Text(active ? 'Desat' : 'Desar'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white54),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          );
        }
        return IconButton(
          tooltip: active ? 'Treure de preferits' : 'Afegir a preferits',
          onPressed: onPressed,
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

  Future<void> _onPressed(
    BuildContext context,
    FavoritesController favorites,
  ) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (!await favorites.hasSession()) {
      if (context.mounted) await _loginAndAdd(context, favorites);
      return;
    }

    try {
      final removing =
          favorites.isFavorite(event.id) && !favorites.isPending(event.id);
      final pending = favorites.toggle(event);
      if (removing) onRemoved?.call();
      await pending;
    } on FavoritesApiException catch (e) {
      if (e.isUnauthorized && context.mounted) {
        // Token caducat: es demana login de nou.
        await _loginAndAdd(context, favorites);
      } else {
        _showError(messenger, e.message);
      }
    } catch (_) {
      _showError(messenger, 'No s\'han pogut actualitzar els preferits');
    }
  }

  /// Demana login i, si va bé, recarrega els preferits del compte i hi
  /// afegeix l'esdeveniment (si el compte ja el tenia, el deixa marcat).
  Future<void> _loginAndAdd(
    BuildContext context,
    FavoritesController favorites,
  ) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final loggedIn = await requestFavoritesLogin(
      context,
      loginBuilder: loginBuilder,
    );
    if (!loggedIn) return;

    await favorites.load();
    if (favorites.isFavorite(event.id)) return;
    try {
      await favorites.toggle(event);
      messenger?.showSnackBar(
        const SnackBar(content: Text('Afegit a preferits')),
      );
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

  /// L'error substitueix el SnackBar actual (p. ex. l'avís "Desfer" que
  /// s'ha mostrat de manera optimista) en lloc de quedar a la cua.
  void _showError(ScaffoldMessengerState? messenger, String message) {
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
