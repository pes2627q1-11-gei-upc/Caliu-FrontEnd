import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'data/event.dart';
import 'data/events_api.dart';
import 'theme/caliu_colors.dart';

class EventDetailScreen extends StatefulWidget {
  const EventDetailScreen({
    super.key,
    required this.eventId,
    this.initialEvent,
  });

  final String eventId;
  final Event? initialEvent;

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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
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
    final date =
        '$day, ${start.day} de ${_months[start.month - 1]}';
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label (properament)')),
    );
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
        const SnackBar(content: Text('L\'enllaç oficial no és vàlid')),
      );
      return;
    }

    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No s\'ha pogut obrir l\'enllaç')),
      );
    }
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
    final chips = <String>{
      ...event.categories,
      ...event.tags,
    }.toList();
    final price = _priceLabel(event);
    final place = event.placeLine;

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
                        child: _roundIconButton(
                          icon: Icons.ios_share,
                          onPressed: () => _stub('Compartir'),
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
                          if (place.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            _infoRow(Icons.place_outlined, place),
                          ],
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
                                  .map(
                                    (label) => Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: CaliuColors.chip,
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        label,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  )
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
                                onPressed: () =>
                                    _openOfficialUrl(event.url!),
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
                  child: OutlinedButton.icon(
                    onPressed: () => _stub('Desar'),
                    icon: const Icon(Icons.bookmark_border),
                    label: const Text('Desar'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white54),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => _stub('Veure ruta'),
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
