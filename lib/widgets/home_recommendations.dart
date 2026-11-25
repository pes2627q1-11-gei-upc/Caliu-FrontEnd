import 'dart:async';

import 'package:flutter/material.dart';

import '../data/auth_session.dart';
import '../data/event.dart';
import '../data/favorites_controller.dart';
import '../data/recommendations_api.dart';
import '../data/recommendations_location.dart';
import '../event_detail_screen.dart';
import '../theme/caliu_colors.dart';
import 'recommendation_card.dart';

/// Secció «Recomanacions» de la pàgina d'Inici (H.U #8).
///
/// Mostra un carrusel horitzontal amb les primeres [maxItems] recomanacions
/// i, al final, una targeta que porta a la pestanya «Per a tu» ([onSeeAll]).
///
/// Només es dibuixa si hi ha recomanacions per ensenyar: sense sessió, mentre
/// carrega, si falla o si la llista és buida no ocupa cap espai (la pestanya
/// «Per a tu» ja s'encarrega de demanar login i d'explicar els errors).
class HomeRecommendations extends StatefulWidget {
  const HomeRecommendations({
    super.key,
    required this.onSeeAll,
    this.api,
    this.session,
    this.favorites,
    this.locate,
    this.isActive = true,
    this.maxItems = defaultMaxItems,
    this.refreshDelay = const Duration(milliseconds: 600),
    this.now,
  });

  /// Obre la pestanya «Per a tu» amb totes les recomanacions.
  final VoidCallback onSeeAll;

  /// Per defecte, [RecommendationsApi].
  final RecommendationsApi? api;

  /// Per defecte, [AuthSession].
  final AuthSessionStore? session;

  /// Per defecte, [FavoritesController.shared].
  final FavoritesController? favorites;

  /// Per defecte, la ubicació del GPS si ja hi ha permís.
  final Future<RecommendationsLocation?> Function()? locate;

  /// Si la pestanya d'Inici és la visible: en tornar-hi es recarrega.
  final bool isActive;

  /// Quantes recomanacions es mostren al carrusel.
  final int maxItems;

  /// Espera abans de recarregar quan canvien els preferits.
  final Duration refreshDelay;

  /// Per als tests; per defecte, `DateTime.now()`.
  final DateTime? now;

  static const defaultMaxItems = 6;

  static const listKey = ValueKey('home-recommendations-list');
  static const seeAllKey = ValueKey('home-recommendations-see-all');
  static const seeAllCardKey = ValueKey('home-recommendations-see-all-card');

  static const _cardWidth = 270.0;
  static const _listHeight = 300.0;

  @override
  State<HomeRecommendations> createState() => _HomeRecommendationsState();
}

class _HomeRecommendationsState extends State<HomeRecommendations> {
  late final RecommendationsApi _api = widget.api ?? RecommendationsApi();
  late final AuthSessionStore _session = widget.session ?? AuthSession();
  late final FavoritesController _favorites =
      widget.favorites ?? FavoritesController.shared;

  List<Event> _events = const [];

  /// Token del compte al qual pertanyen [_events]. Si la sessió canvia, les
  /// recomanacions de l'anterior es descarten abans de demanar-ne de noves.
  String? _eventsToken;

  int _request = 0;
  Timer? _refreshTimer;
  Set<String> _favoriteIds = {};

  @override
  void initState() {
    super.initState();
    _favoriteIds = _currentFavoriteIds();
    _favorites.addListener(_favoritesChanged);
    if (widget.isActive) _load();
  }

  @override
  void didUpdateWidget(HomeRecommendations oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) _load();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _favorites.removeListener(_favoritesChanged);
    super.dispose();
  }

  Set<String> _currentFavoriteIds() =>
      _favorites.favorites.map((event) => event.id).toSet();

  /// El marcat desapareix a l'instant (filtre de [_visible]) i poc després es
  /// tornen a demanar. Com a «Per a tu», només es recarrega si els preferits
  /// han canviat de veritat: el controlador notifica també en carregar.
  void _favoritesChanged() {
    if (!mounted) return;
    final ids = _currentFavoriteIds();
    final changed =
        ids.length != _favoriteIds.length || !ids.containsAll(_favoriteIds);
    _favoriteIds = ids;
    setState(() {});
    if (!changed || !widget.isActive) return;
    _refreshTimer?.cancel();
    _refreshTimer = Timer(widget.refreshDelay, _load);
  }

  /// Buida la secció i desvincula les dades de qualsevol compte.
  void _clear() {
    _eventsToken = null;
    setState(() => _events = const []);
  }

  /// Els preferits ja marcats no es recomanen (com a «Per a tu»).
  List<Event> get _visible => _events
      .where((event) => !_favorites.isFavorite(event.id))
      .take(widget.maxItems)
      .toList();

  /// Recàrrega silenciosa. Les dades queden vinculades al token amb què
  /// s'han demanat: si la sessió ha canviat, es buiden abans de la petició i
  /// les respostes del compte anterior es descarten. Si falla, només es manté
  /// el que hi havia quan és del mateix compte.
  Future<void> _load() async {
    final request = ++_request;
    try {
      final token = await _session.readToken();
      if (!mounted || request != _request) return;
      if (token == null || token.isEmpty) {
        _clear();
        return;
      }
      if (token != _eventsToken) _clear();

      RecommendationsLocation? position;
      try {
        final locate = widget.locate ?? recommendationsLocationIfAllowed;
        position = await locate().timeout(const Duration(seconds: 6));
      } catch (_) {
        position = null;
      }
      if (!mounted || request != _request) return;
      // Se'n demanen més de les que es mostren per si n'hi ha de preferides.
      final page = await _api.fetchRecommendations(
        token: token,
        lat: position?.lat,
        lng: position?.lng,
        limit: widget.maxItems * 2,
      );
      if (!mounted || request != _request) return;
      // La sessió pot haver canviat mentre esperàvem la resposta.
      if (await _session.readToken() != token) {
        if (mounted && request == _request) _clear();
        return;
      }
      if (!mounted || request != _request) return;
      _eventsToken = token;
      setState(() => _events = page.items);
    } on RecommendationsApiException catch (e) {
      if (!mounted || request != _request) return;
      // Sessió caducada: la secció s'amaga; «Per a tu» gestiona el login.
      if (e.isUnauthorized) _clear();
    } catch (_) {
      // P. ex. si falla el secure storage: no podem saber de qui són les
      // dades, així que no se'n mostra cap.
      if (mounted && request == _request) _clear();
    }
  }

  void _openDetail(Event event) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EventDetailScreen(
          eventId: event.id,
          initialEvent: event,
          favorites: _favorites,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    if (visible.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'PER A TU',
                        style: TextStyle(
                          color: CaliuColors.red,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Recomanacions',
                        style: TextStyle(
                          color: CaliuColors.maroonDeep,
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  key: HomeRecommendations.seeAllKey,
                  onPressed: widget.onSeeAll,
                  style: TextButton.styleFrom(
                    foregroundColor: CaliuColors.red,
                    textStyle: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  child: const Text('Veure tot'),
                ),
              ],
            ),
          ),
          SizedBox(
            height: HomeRecommendations._listHeight,
            child: ListView.separated(
              key: HomeRecommendations.listKey,
              scrollDirection: Axis.horizontal,
              // Marge vertical perquè no es retalli l'ombra de les targetes.
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
              itemCount: visible.length + 1,
              separatorBuilder: (context, index) => const SizedBox(width: 14),
              itemBuilder: (context, index) {
                if (index == visible.length) {
                  return _SeeAllCard(onTap: widget.onSeeAll);
                }
                final event = visible[index];
                return SizedBox(
                  width: HomeRecommendations._cardWidth,
                  child: RecommendationCard(
                    key: ValueKey('home-recommendation-${event.id}'),
                    event: event,
                    favorites: _favorites,
                    now: widget.now,
                    onTap: () => _openDetail(event),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Última targeta del carrusel: porta a la pestanya «Per a tu».
class _SeeAllCard extends StatelessWidget {
  const _SeeAllCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 170,
      child: Material(
        key: HomeRecommendations.seeAllCardKey,
        color: CaliuColors.maroon,
        borderRadius: BorderRadius.circular(RecommendationCard.radius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: const Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: CaliuColors.red,
                  foregroundColor: Colors.white,
                  child: Icon(Icons.arrow_forward),
                ),
                SizedBox(height: 14),
                Text(
                  'Veure totes les recomanacions',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
