import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import 'data/auth_session.dart';
import 'data/event.dart';
import 'data/favorites_controller.dart';
import 'data/recommendations_api.dart';
import 'event_detail_screen.dart';
import 'login_screen.dart';
import 'theme/caliu_colors.dart';
import 'widgets/centered_message.dart';
import 'widgets/event_list_tile.dart';
import 'widgets/favorite_button.dart';

/// Ubicació per ordenar les recomanacions per proximitat.
typedef RecommendationsLocation = ({double lat, double lng});

/// Pestanya «Per a tu» (H.U #8, tasca #122): esdeveniments recomanats segons
/// els preferits, les preferències i la ubicació de l'usuari.
///
/// No mostra els esdeveniments que ja són preferits: el backend exclou els
/// que té desats, però els preferits de l'app encara són locals
/// (`MockFavoritesApi`) i es filtren aquí; en marcar-ne un, desapareix a
/// l'instant. Quan canvien els preferits es tornen a demanar les
/// recomanacions (tasca #160): ara només hi té efecte el filtre local, i
/// quan els preferits es desin al backend també s'ajustarà l'ordre.
class RecommendationsScreen extends StatefulWidget {
  const RecommendationsScreen({
    super.key,
    this.api,
    this.session,
    this.favorites,
    this.locate,
    this.isActive = true,
    this.refreshDelay = const Duration(milliseconds: 600),
    this.loginBuilder,
  });

  /// Per defecte, [RecommendationsApi].
  final RecommendationsApi? api;

  /// Per defecte, [AuthSession].
  final AuthSessionStore? session;

  /// Per defecte, [FavoritesController.shared].
  final FavoritesController? favorites;

  /// Ubicació per ordenar per proximitat. Per defecte, la del GPS si ja hi ha
  /// permís (sense demanar-lo); null si no se'n pot obtenir.
  final Future<RecommendationsLocation?> Function()? locate;

  /// Si la pestanya és la visible. No es carrega res fins que ho és per
  /// primera vegada (l'`IndexedStack` munta totes les pestanyes en obrir
  /// l'app) i, en tornar-hi, es recarrega en segon pla.
  final bool isActive;

  /// Espera abans de tornar a demanar les recomanacions quan canvien els
  /// preferits, per agrupar diversos tocs seguits.
  final Duration refreshDelay;

  /// Per als tests; per defecte, la pantalla de login de l'app.
  final WidgetBuilder? loginBuilder;

  @override
  State<RecommendationsScreen> createState() => _RecommendationsScreenState();
}

class _RecommendationsScreenState extends State<RecommendationsScreen> {
  late final RecommendationsApi _api = widget.api ?? RecommendationsApi();
  late final AuthSessionStore _session = widget.session ?? AuthSession();
  late final FavoritesController _favorites =
      widget.favorites ?? FavoritesController.shared;

  List<Event> _events = const [];
  bool _loading = false;
  bool _loadedOnce = false;
  bool _needsLogin = false;
  bool _usedLocation = false;
  String? _error;
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
  void didUpdateWidget(RecommendationsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _loadedOnce ? _load(quiet: true) : _load();
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _favorites.removeListener(_favoritesChanged);
    super.dispose();
  }

  Set<String> _currentFavoriteIds() =>
      _favorites.favorites.map((event) => event.id).toSet();

  /// Els preferits ja marcats no es recomanen.
  List<Event> get _visible =>
      _events.where((event) => !_favorites.isFavorite(event.id)).toList();

  /// Tasca #160: l'esdeveniment marcat desapareix a l'instant (el filtre de
  /// [_visible]) i, poc després, es tornen a demanar les recomanacions. Si la
  /// pestanya no es veu, ja es recarregarà en tornar-hi.
  void _favoritesChanged() {
    if (!mounted) return;
    final ids = _currentFavoriteIds();
    final changed =
        ids.length != _favoriteIds.length || !ids.containsAll(_favoriteIds);
    _favoriteIds = ids;
    setState(() {});
    if (!changed || _needsLogin || !_loadedOnce || !widget.isActive) return;
    _refreshTimer?.cancel();
    _refreshTimer = Timer(widget.refreshDelay, () => _load(quiet: true));
  }

  /// [quiet]: recàrrega en segon pla, sense amagar la llista actual. Si
  /// falla, la llista es manté i s'avisa amb un SnackBar.
  Future<void> _load({bool quiet = false}) async {
    final request = ++_request;
    _loadedOnce = true;
    final background = quiet && _events.isNotEmpty;
    if (!background) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    String? token;
    try {
      token = await _session.readToken();
      if (!mounted || request != _request) return;
      if (token == null || token.isEmpty) {
        _showLogin();
        return;
      }

      final position = await _position();
      if (!mounted || request != _request) return;
      final page = await _api.fetchRecommendations(
        token: token,
        lat: position?.lat,
        lng: position?.lng,
      );
      if (!mounted || request != _request) return;
      setState(() {
        _events = page.items;
        _usedLocation = position != null;
        _needsLogin = false;
        _loading = false;
        _error = null;
      });
    } on RecommendationsApiException catch (e) {
      if (!mounted || request != _request) return;
      if (e.isUnauthorized) {
        await _expireSession(token);
        return;
      }
      _showError(e.message, background: background);
    } catch (_) {
      // P. ex. si falla el secure storage: mai no es queda carregant.
      if (!mounted || request != _request) return;
      _showError(
        'No s\'han pogut carregar les recomanacions. Torna-ho a provar.',
        background: background,
      );
    }
  }

  void _showLogin() {
    setState(() {
      _needsLogin = true;
      _events = const [];
      _loading = false;
      _error = null;
    });
  }

  void _showError(String message, {required bool background}) {
    setState(() {
      _loading = false;
      if (!background) _error = message;
    });
    if (background) {
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  /// Token caducat: es tanca la sessió (com fan Perfil i Preferències) i es
  /// demana tornar a entrar. Només s'esborra si és el mateix que ha fallat.
  Future<void> _expireSession(String? token) async {
    try {
      if (token != null && await _session.readToken() == token) {
        await _session.clear();
      }
    } catch (_) {
      // Encara que falli l'emmagatzematge, la pantalla demana iniciar sessió.
    }
    _favorites.clear();
    if (mounted) _showLogin();
  }

  Future<RecommendationsLocation?> _position() async {
    try {
      return await (widget.locate ?? _gpsIfAllowed)().timeout(
        const Duration(seconds: 6),
      );
    } catch (_) {
      return null;
    }
  }

  /// No demana permís: el mapa ja ho fa. Primer l'última posició coneguda
  /// (no existeix a web) i, si no n'hi ha, una de nova amb límit de temps.
  static Future<RecommendationsLocation?> _gpsIfAllowed() async {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    final permission = await Geolocator.checkPermission();
    if (permission != LocationPermission.always &&
        permission != LocationPermission.whileInUse) {
      return null;
    }
    final last = kIsWeb ? null : await Geolocator.getLastKnownPosition();
    final position =
        last ??
        await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium,
          timeLimit: const Duration(seconds: 5),
        );
    return (lat: position.latitude, lng: position.longitude);
  }

  Future<void> _login() async {
    final builder = widget.loginBuilder;
    final loggedIn = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (context) => builder != null
            ? builder(context)
            : const LoginScreen(
                notice: 'Inicia sessió per veure les teves recomanacions.',
              ),
      ),
    );
    if (loggedIn == true && mounted) {
      await _favorites.load();
      // Carregar els preferits pot programar un refresc: ja carreguem ara.
      _refreshTimer?.cancel();
      if (mounted) await _load();
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
    return Scaffold(
      backgroundColor: CaliuColors.beige,
      appBar: AppBar(
        backgroundColor: CaliuColors.maroon,
        foregroundColor: Colors.white,
        title: const Text('Per a tu'),
      ),
      body: Column(
        children: [
          if (!_needsLogin)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _loading
                          ? 'Carregant recomanacions…'
                          : _error != null || !_loadedOnce
                          ? ''
                          : visible.length == 1
                          ? '1 recomanació'
                          : '${visible.length} recomanacions',
                      key: const ValueKey('recommendations-count'),
                      style: const TextStyle(
                        color: CaliuColors.textMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _loading ? null : () => _load(quiet: true),
                    child: const Text('Actualitzar'),
                  ),
                ],
              ),
            ),
          Expanded(
            child: RefreshIndicator(
              color: CaliuColors.red,
              onRefresh: () => _load(quiet: true),
              child: _buildBody(visible),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(List<Event> visible) {
    if (!_loadedOnce || (_loading && _events.isEmpty)) {
      return const Center(
        child: CircularProgressIndicator(color: CaliuColors.red),
      );
    }

    if (_needsLogin) {
      return CenteredMessage(
        icon: Icons.star_outline,
        title: 'Inicia sessió per veure recomanacions per a tu',
        subtitle:
            'Les fem a partir dels teus preferits, les teves preferències i '
            'la teva ubicació.',
        action: FilledButton.icon(
          onPressed: _login,
          icon: const Icon(Icons.login),
          label: const Text('Inicia sessió'),
          style: FilledButton.styleFrom(backgroundColor: CaliuColors.red),
        ),
      );
    }

    if (_error case final error?) {
      return CenteredMessage(
        icon: Icons.cloud_off,
        title: error,
        action: FilledButton(
          onPressed: () => _load(),
          style: FilledButton.styleFrom(backgroundColor: CaliuColors.red),
          child: const Text('Tornar a provar'),
        ),
      );
    }

    if (visible.isEmpty) {
      // Amb ubicació, el backend només busca dins del radi d'activitat.
      return CenteredMessage(
        icon: Icons.star_outline,
        title: _usedLocation
            ? 'No hi ha recomanacions dins del teu radi d\'activitat'
            : 'Encara no tenim recomanacions per a tu',
        subtitle: _usedLocation
            ? 'Pots ampliar el radi a Perfil → Preferències.'
            : 'Marca alguns esdeveniments com a preferits o tria les teves '
                  'categories a Perfil → Preferències.',
      );
    }

    return ListView.separated(
      key: const ValueKey('recommendations-list'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: visible.length,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final event = visible[index];
        return EventListTile(
          key: ValueKey('recommendation-${event.id}'),
          event: event,
          subtitle: eventListSubtitle(event),
          onTap: () => _openDetail(event),
          trailing: FavoriteButton(event: event, controller: _favorites),
        );
      },
    );
  }
}
