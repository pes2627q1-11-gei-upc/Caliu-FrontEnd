import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'data/event.dart';
import 'data/events_api.dart';
import 'data/favorite_alerts_controller.dart';
import 'data/favorites_controller.dart';
import 'map_view.dart';
import 'theme/caliu_colors.dart';
import 'widgets/alerts_toggle_button.dart';
import 'widgets/caliu_chip.dart';
import 'widgets/favorite_button.dart';

class EventDetailScreen extends StatefulWidget {
  const EventDetailScreen({
    super.key,
    required this.eventId,
    this.initialEvent,
    this.favorites,
    this.alerts,
    this.showAlerts = favoriteAlertsAvailable,
  });

  final String eventId;
  final Event? initialEvent;

  /// Per defecte, [FavoritesController.shared].
  final FavoritesController? favorites;

  /// Per defecte, [FavoriteAlertsController.shared].
  final FavoriteAlertsController? alerts;

  /// Mostrar la campana d'alertes. Per defecte, només si les notificacions
  /// ja funcionen ([favoriteAlertsAvailable]).
  final bool showAlerts;

  @override
  State<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends State<EventDetailScreen> {
  final EventsApi _api = EventsApi();

  late Event? _event = widget.initialEvent;
  bool _loading = true;
  String? _error;

  static const _weekdays = [
    'Dilluns',
    'Dimarts',
    'Dimecres',
    'Dijous',
    'Divendres',
    'Dissabte',
    'Diumenge',
  ];
  static const _months = [
    'gener',
    'febrer',
    'març',
    'abril',
    'maig',
    'juny',
    'juliol',
    'agost',
    'setembre',
    'octubre',
    'novembre',
    'desembre',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _event == null;
      _error = null;
    });

    try {
      final fresh = await _api.fetchById(widget.eventId);
      if (!mounted) return;
      setState(() {
        _event = fresh;
        _loading = false;
      });
    } on EventsApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (_event == null) _error = e.message;
      });
      if (_event != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (_event == null) _error = 'Error carregant l\'esdeveniment';
      });
    }
  }

  String _formatWhen(Event event) {
    final start = event.startDate?.toLocal();
    if (start == null) {
      return event.schedule?.trim().isNotEmpty == true
          ? event.schedule!.trim()
          : 'Data per confirmar';
    }

    final day = _weekdays[start.weekday - 1];
    final date = '$day, ${start.day} de ${_months[start.month - 1]}';
    final time =
        '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}';
    final schedule = event.schedule?.trim();
    if (schedule != null && schedule.isNotEmpty) {
      return '$date · $schedule';
    }
    return '$date · $time';
  }

  String? _priceLabel(Event event) {
    if (event.price == null) return null;
    if (event.price == 0) return 'Gratuït';
    return '${event.price!.toStringAsFixed(event.price! % 1 == 0 ? 0 : 2)} €';
  }

  void _stub(String label) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('$label (properament)')));
  }

  Future<void> _openOfficialUrl(String rawUrl) async {
    var value = rawUrl.trim();
    if (value.isEmpty) return;

    if (!value.startsWith('http://') && !value.startsWith('https://')) {
      value = 'https://$value';
    }

    final uri = Uri.tryParse(value);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('L’enllaç oficial no és vàlid')),
      );
      return;
    }

    await _launchExternalUrl(uri, 'No s’ha pogut obrir l’enllaç');
  }

  Future<void> _openRoute(Event event) async {
    final uri = event.googleMapsDirectionsUri;
    if (uri == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('La ubicació de l’esdeveniment no està disponible'),
        ),
      );
      return;
    }

    await _launchExternalUrl(uri, 'No s’ha pogut obrir la ruta a Google Maps');
  }

  Future<void> _launchExternalUrl(Uri uri, String errorMessage) async {
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    } on PlatformException {
      // El dispositiu no ha pogut obrir l'enllaç.
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(errorMessage)));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _event == null) {
      return const Scaffold(
        backgroundColor: CaliuColors.beige,
        body: Center(child: CircularProgressIndicator(color: CaliuColors.red)),
      );
    }

    if (_error != null && _event == null) {
      return Scaffold(
        backgroundColor: CaliuColors.beige,
        appBar: AppBar(
          backgroundColor: CaliuColors.maroon,
          foregroundColor: Colors.white,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _load,
                  style: FilledButton.styleFrom(
                    backgroundColor: CaliuColors.red,
                  ),
                  child: const Text('Tornar a provar'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final event = _event!;
    final categoryLabel = event.categories.isNotEmpty
        ? event.categories.join(' | ').toUpperCase()
        : null;
    final chips = <String>{...event.categories, ...event.tags}.toList();
    final price = _priceLabel(event);
    final place = event.placeLine;
    final calendarUri = event.googleCalendarUri();

    return Scaffold(
      backgroundColor: CaliuColors.beige,
      body: Column(
        children: [
          Expanded(
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Stack(
                    children: [
                      SizedBox(
                        height: 280,
                        width: double.infinity,
                        child: event.imageUrl != null
                            ? Image.network(
                                event.imageUrl!,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) =>
                                    _imagePlaceholder(),
                              )
                            : _imagePlaceholder(),
                      ),
                      Positioned(
                        top: MediaQuery.paddingOf(context).top + 8,
                        left: 12,
                        child: _roundIconButton(
                          icon: Icons.arrow_back,
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ),
                      Positioned(
                        top: MediaQuery.paddingOf(context).top + 8,
                        right: 12,
                        child: Row(
                          children: [
                            // Campana d'alertes: només si és un preferit.
                            ListenableBuilder(
                              listenable:
                                  widget.favorites ??
                                  FavoritesController.shared,
                              builder: (context, _) {
                                final favorites =
                                    widget.favorites ??
                                    FavoritesController.shared;
                                if (!widget.showAlerts ||
                                    !favorites.isFavorite(event.id)) {
                                  return const SizedBox.shrink();
                                }
                                return Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: Material(
                                    color: Colors.black45,
                                    shape: const CircleBorder(),
                                    child: AlertsToggleButton(
                                      event: event,
                                      alerts: widget.alerts,
                                      favorites: favorites,
                                      color: Colors.white70,
                                      activeColor: Colors.white,
                                      size: 22,
                                    ),
                                  ),
                                );
                              },
                            ),
                            _roundIconButton(
                              icon: Icons.ios_share,
                              onPressed: () => _stub('Compartir'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (_loading)
                  const SliverToBoxAdapter(
                    child: LinearProgressIndicator(
                      color: CaliuColors.red,
                      backgroundColor: CaliuColors.beige,
                    ),
                  ),
                SliverToBoxAdapter(
                  child: Transform.translate(
                    offset: const Offset(0, -24),
                    child: Container(
                      width: double.infinity,
                      decoration: const BoxDecoration(
                        color: CaliuColors.beigeCard,
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(28),
                        ),
                      ),
                      padding: const EdgeInsets.fromLTRB(20, 28, 20, 32),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (categoryLabel != null) ...[
                            Text(
                              categoryLabel,
                              style: const TextStyle(
                                color: CaliuColors.red,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                                letterSpacing: 0.6,
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],
                          Text(
                            event.title,
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              height: 1.15,
                              color: CaliuColors.maroonDeep,
                            ),
                          ),
                          const SizedBox(height: 14),
                          _infoRow(Icons.schedule, _formatWhen(event)),
                          if (calendarUri != null)
                            TextButton.icon(
                              onPressed: () => _launchExternalUrl(
                                calendarUri,
                                'No s’ha pogut obrir Google Calendar',
                              ),
                              icon: const Icon(Icons.event_available_outlined),
                              label: const Text('Afegir al calendari'),
                              style: TextButton.styleFrom(
                                foregroundColor: CaliuColors.red,
                              ),
                            ),
                          if (place.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            _infoRow(Icons.place_outlined, place),
                          ],
                          if (event.hasLocation)
                            TextButton.icon(
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) =>
                                      MapView.forEvent(event: event),
                                ),
                              ),
                              icon: const Icon(Icons.map_outlined),
                              label: const Text('Veure al mapa'),
                              style: TextButton.styleFrom(
                                foregroundColor: CaliuColors.red,
                              ),
                            ),
                          if (price != null) ...[
                            const SizedBox(height: 8),
                            _infoRow(Icons.payments_outlined, price),
                          ],
                          if (chips.isNotEmpty) ...[
                            const SizedBox(height: 18),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: chips
                                  .map((label) => CaliuChip(label: label))
                                  .toList(),
                            ),
                          ],
                          if (event.description != null &&
                              event.description!.trim().isNotEmpty) ...[
                            const SizedBox(height: 28),
                            const Text(
                              'SOBRE L\'ESDEVENIMENT',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.8,
                                color: CaliuColors.maroon,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              event.description!.trim(),
                              style: const TextStyle(
                                fontSize: 15,
                                height: 1.45,
                                color: CaliuColors.textMuted,
                              ),
                            ),
                          ],
                          if (event.url != null &&
                              event.url!.trim().isNotEmpty) ...[
                            const SizedBox(height: 24),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: () => _openOfficialUrl(event.url!),
                                icon: const Icon(Icons.open_in_new),
                                label: const Text('Web oficial'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: CaliuColors.red,
                                  side: const BorderSide(
                                    color: CaliuColors.red,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            color: CaliuColors.maroon,
            padding: EdgeInsets.fromLTRB(
              16,
              12,
              16,
              12 + MediaQuery.paddingOf(context).bottom,
            ),
            child: Row(
              children: [
                Expanded(
                  child: FavoriteButton(
                    event: event,
                    controller: widget.favorites,
                    showBookmark: true,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => _openRoute(event),
                    style: FilledButton.styleFrom(
                      backgroundColor: CaliuColors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Veure ruta'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _imagePlaceholder() {
    return Container(
      color: CaliuColors.maroon,
      child: const Center(
        child: Icon(Icons.event, size: 64, color: Colors.white54),
      ),
    );
  }

  Widget _roundIconButton({
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return Material(
      color: Colors.black45,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: CaliuColors.textMuted),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 14,
              color: CaliuColors.textMuted,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }
}
