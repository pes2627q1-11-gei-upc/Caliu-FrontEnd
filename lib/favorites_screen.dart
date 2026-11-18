import 'package:flutter/material.dart';

import 'data/event.dart';
import 'data/event_when.dart';
import 'data/favorites_controller.dart';
import 'event_detail_screen.dart';
import 'theme/caliu_colors.dart';
import 'widgets/event_list_tile.dart';
import 'widgets/favorite_button.dart';

/// Llista de preferits de l'usuari, accessible des del perfil (tasca #190).
///
/// Es recarrega en obrir-la i estirant cap avall. Treure el cor d'un
/// esdeveniment el fa desaparèixer de la llista a l'instant.
class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key, this.favorites, this.now});

  /// Per defecte, [FavoritesController.shared].
  final FavoritesController? favorites;

  /// Per als tests; per defecte, `DateTime.now()`.
  final DateTime? now;

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  late final FavoritesController _favorites =
      widget.favorites ?? FavoritesController.shared;

  @override
  void initState() {
    super.initState();
    _favorites.load();
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
    return Scaffold(
      backgroundColor: CaliuColors.beige,
      appBar: AppBar(
        backgroundColor: CaliuColors.maroonDeep,
        foregroundColor: Colors.white,
        title: const Text('Preferits'),
      ),
      body: ListenableBuilder(
        listenable: _favorites,
        builder: (context, _) => RefreshIndicator(
          color: CaliuColors.red,
          onRefresh: _favorites.load,
          child: _buildBody(),
        ),
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
      return _Message(
        icon: error.isUnauthorized ? Icons.lock_outline : Icons.cloud_off,
        title: error.message,
        action: FilledButton(
          onPressed: _favorites.load,
          style: FilledButton.styleFrom(backgroundColor: CaliuColors.red),
          child: const Text('Tornar a provar'),
        ),
      );
    }

    if (favorites.isEmpty) {
      return const _Message(
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
        return EventListTile(
          key: ValueKey(event.id),
          event: event,
          subtitle: _subtitle(event),
          onTap: () => _openDetail(event),
          trailing: FavoriteButton(event: event, controller: _favorites),
        );
      },
    );
  }
}

/// Missatge centrat (llista buida o error) que es pot estirar per recarregar.
class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 56, color: CaliuColors.textMuted),
                  const SizedBox(height: 16),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: CaliuColors.maroonDeep,
                    ),
                  ),
                  if (subtitle case final subtitle?) ...[
                    const SizedBox(height: 8),
                    Text(
                      subtitle,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: CaliuColors.textMuted),
                    ),
                  ],
                  if (action case final action?) ...[
                    const SizedBox(height: 20),
                    action,
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
