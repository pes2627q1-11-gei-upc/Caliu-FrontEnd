import 'package:flutter/material.dart';

import '../data/event.dart';
import '../data/event_when.dart';
import '../data/favorites_controller.dart';
import '../theme/caliu_colors.dart';
import 'favorite_button.dart';

/// Targeta d'una recomanació (H.U #8): imatge a dalt amb l'etiqueta de la
/// categoria i el cor de preferits, i a sota el títol i «quan · on».
///
/// És la mateixa a la secció «Recomanacions» d'Inici (carrusel horitzontal)
/// i a la pestanya «Per a tu» (llista vertical), perquè es vegin igual.
class RecommendationCard extends StatelessWidget {
  const RecommendationCard({
    super.key,
    required this.event,
    required this.onTap,
    this.favorites,
    this.imageHeight = compactImageHeight,
    this.now,
  });

  final Event event;
  final VoidCallback onTap;

  /// Per defecte, [FavoritesController.shared].
  final FavoritesController? favorites;

  final double imageHeight;

  /// Per als tests; per defecte, `DateTime.now()`.
  final DateTime? now;

  /// Alçada de la imatge al carrusel d'Inici.
  static const compactImageHeight = 150.0;

  /// Alçada de la imatge quan la targeta ocupa tota l'amplada.
  static const wideImageHeight = 180.0;

  static const radius = 20.0;

  /// Text en vermell sota el títol: «quan · on · distància».
  static String detailsLine(Event event, DateTime now) {
    final place = event.shortPlace;
    return [
      previewWhen(event, now),
      if (place.isNotEmpty) place,
      if (event.distanceMeters != null)
        '${(event.distanceMeters! / 1000).toStringAsFixed(1)} km',
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final category = event.categories.isNotEmpty
        ? event.categories.first
        : null;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: CaliuColors.maroonDeep.withValues(alpha: 0.12),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: imageHeight,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    event.imageUrl != null
                        ? Image.network(
                            event.imageUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                const _ImagePlaceholder(),
                          )
                        : const _ImagePlaceholder(),
                    if (category != null)
                      Positioned(
                        top: 12,
                        left: 12,
                        right: 60,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: CategoryBadge(label: category),
                        ),
                      ),
                    Positioned(
                      top: 6,
                      right: 6,
                      child: DecoratedBox(
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: FavoriteButton(
                          event: event,
                          controller: favorites,
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      event.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: CaliuColors.maroonDeep,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      detailsLine(event, now ?? DateTime.now()),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: CaliuColors.red,
                        fontSize: 14,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Etiqueta arrodonida de la categoria sobre la imatge (vermella o groga).
class CategoryBadge extends StatelessWidget {
  const CategoryBadge({super.key, required this.label});

  final String label;

  static const _amber = Color(0xFFF7C33C);

  @override
  Widget build(BuildContext context) {
    // Alterna els dos colors del disseny de manera estable per categoria.
    final amber = label.codeUnits.fold<int>(0, (a, b) => a + b).isOdd;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: amber ? _amber : CaliuColors.red,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: amber ? CaliuColors.maroonDeep : Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _ImagePlaceholder extends StatelessWidget {
  const _ImagePlaceholder();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: CaliuColors.maroon,
      child: Center(child: Icon(Icons.event, color: Colors.white54, size: 40)),
    );
  }
}
