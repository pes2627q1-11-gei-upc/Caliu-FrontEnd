import 'package:flutter/material.dart';

import 'data/event.dart';
import 'data/event_when.dart';
import 'data/favorites_api.dart';
import 'data/favorites_controller.dart';
import 'event_detail_screen.dart';
import 'login_screen.dart';
import 'theme/caliu_colors.dart';
import 'widgets/centered_message.dart';
import 'widgets/event_list_tile.dart';
import 'widgets/favorite_button.dart';
import 'widgets/favorites_login_prompt.dart';

/// Llista de preferits de l'usuari per a la pestanya Guardats del perfil
/// (tasques #190 i #152). No té Scaffold propi.
///
/// Es recarrega en mostrar-se i estirant cap avall. Treure el cor o lliscar
/// la targeta cap a l'esquerra el fa desaparèixer a l'instant, amb l'opció
/// de desfer-ho (tasca #167).
class FavoritesList extends StatefulWidget {
  const FavoritesList({super.key, this.favorites, this.now, this.loginBuilder});

  /// Per defecte, [FavoritesController.shared].
  final FavoritesController? favorites;

  /// Per als tests; per defecte, `DateTime.now()`.
  final DateTime? now;

  /// Per als tests; per defecte, la pantalla de login de l'app.
  final FavoritesLoginBuilder? loginBuilder;

  @override
  State<FavoritesList> createState() => _FavoritesListState();
}

class _FavoritesListState extends State<FavoritesList> {
  late final FavoritesController _favorites =
      widget.favorites ?? FavoritesController.shared;

  @override
  void initState() {
    super.initState();
    _favorites.load();
  }

  /// Sense sessió: obre el login i, si va bé, carrega els preferits (#191).
  Future<void> _login() async {
    final builder = widget.loginBuilder;
    final loggedIn = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (context) => builder != null
            ? builder(context)
            : const LoginScreen(notice: favoritesLoginNotice),
      ),
    );
    if (loggedIn == true) await _favorites.load();
  }

  /// Lliscar la targeta: la treu dels preferits.
  Future<void> _swipeRemove(Event event) async {
    final messenger = ScaffoldMessenger.of(context);
    final pending = _favorites.toggle(event);
    _showUndo(event);
    try {
      await pending;
    } on FavoritesApiException catch (e) {
      _showError(messenger, e.message);
    } catch (_) {
      _showError(messenger, 'No s\'ha pogut treure dels preferits');
    }
  }

  /// SnackBar "Eliminat de preferits" amb l'opció de desfer.
  void _showUndo(Event event) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('"${event.title}" eliminat de preferits'),
          action: SnackBarAction(
            label: 'Desfer',
            textColor: CaliuColors.redSoft,
            onPressed: () => _undo(event),
          ),
        ),
      );
  }

  Future<void> _undo(Event event) async {
    final messenger = ScaffoldMessenger.of(context);
    // Si la petició d'eliminar encara no ha acabat, s'espera abans de desfer.
    await _favorites.settled(event.id);
    if (_favorites.isFavorite(event.id)) return;
    try {
      await _favorites.toggle(event);
    } on FavoritesApiException catch (e) {
      _showError(messenger, e.message);
    } catch (_) {
      _showError(messenger, 'No s\'ha pogut tornar a afegir als preferits');
    }
  }

  void _showError(ScaffoldMessengerState messenger, String message) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _openDetail(Event event) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EventDetailScreen(
          eventId: event.id,
          initialEvent: event,
          favorites: widget.favorites,
        ),
      ),
    );
  }

  String _subtitle(Event event) {
    final parts = <String>[
      previewWhen(event, widget.now ?? DateTime.now()),
      if (event.shortPlace.isNotEmpty) event.shortPlace,
    ];
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _favorites,
      builder: (context, _) => RefreshIndicator(
        color: CaliuColors.red,
        onRefresh: _favorites.load,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    final favorites = _favorites.favorites;

    if (_favorites.isLoading && favorites.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: CaliuColors.red),
      );
    }

    if (_favorites.error case final error? when favorites.isEmpty) {
      if (error.isUnauthorized) {
        return CenteredMessage(
          icon: Icons.lock_outline,
          title: 'Inicia sessió per veure els teus preferits',
          action: FilledButton.icon(
            onPressed: _login,
            icon: const Icon(Icons.login),
            label: const Text('Inicia sessió'),
            style: FilledButton.styleFrom(backgroundColor: CaliuColors.red),
          ),
        );
      }
      return CenteredMessage(
        icon: Icons.cloud_off,
        title: error.message,
        action: FilledButton(
          onPressed: _favorites.load,
          style: FilledButton.styleFrom(backgroundColor: CaliuColors.red),
          child: const Text('Tornar a provar'),
        ),
      );
    }

    if (favorites.isEmpty) {
      return const CenteredMessage(
        icon: Icons.favorite_border,
        title: 'Encara no tens preferits',
        subtitle:
            'Toca el cor d\'un esdeveniment per guardar-lo aquí i '
            'trobar-lo fàcilment.',
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      itemCount: favorites.length,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final event = favorites[index];
        return Dismissible(
          key: ValueKey(event.id),
          direction: _favorites.isPending(event.id)
              ? DismissDirection.none
              : DismissDirection.endToStart,
          background: const _SwipeBackground(),
          onDismissed: (_) => _swipeRemove(event),
          child: EventListTile(
            event: event,
            subtitle: _subtitle(event),
            onTap: () => _openDetail(event),
            trailing: FavoriteButton(
              event: event,
              controller: _favorites,
              loginBuilder: widget.loginBuilder,
              onRemoved: () => _showUndo(event),
            ),
          ),
        );
      },
    );
  }
}

/// Fons vermell que apareix mentre es llisca una targeta per treure-la.
class _SwipeBackground extends StatelessWidget {
  const _SwipeBackground();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: CaliuColors.red,
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Align(
        alignment: Alignment.centerRight,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Treure',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(width: 8),
              Icon(Icons.heart_broken_outlined, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}
