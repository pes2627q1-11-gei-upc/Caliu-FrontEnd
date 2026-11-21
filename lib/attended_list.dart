import 'package:flutter/material.dart';

import 'activity_list.dart';
import 'data/attended_api.dart';
import 'data/event.dart';
import 'event_detail_screen.dart';
import 'login_screen.dart';
import 'theme/caliu_colors.dart';
import 'widgets/centered_message.dart';
import 'widgets/event_list_tile.dart';

/// Historial complet d'esdeveniments passats als quals ha assistit l'usuari,
/// agrupats per any, per a la pestanya Historial del perfil (tasca #169,
/// H.U #51). Es carrega en mostrar-se i estirant cap avall.
class AttendedList extends StatefulWidget {
  const AttendedList({super.key, this.api, this.now, this.loginBuilder});

  /// Per defecte, [createAttendedApi].
  final AttendedApi? api;

  /// Per als tests; per defecte, `DateTime.now()`.
  final DateTime? now;

  /// Per als tests; per defecte, la pantalla de login de l'app.
  final WidgetBuilder? loginBuilder;

  @override
  State<AttendedList> createState() => _AttendedListState();
}

class _AttendedListState extends State<AttendedList> {
  late final AttendedApi _api = widget.api ?? createAttendedApi();

  List<Event>? _events;
  AttendedApiException? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final events = await _api.fetchAttended();
      if (!mounted) return;
      setState(() {
        _events = events;
        _error = null;
        _loading = false;
      });
    } on AttendedApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _events = null;
        _error = e;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _events = null;
        _error = const AttendedApiException(
          'No s\'ha pogut carregar l\'historial',
        );
        _loading = false;
      });
    }
  }

  Future<void> _login() async {
    final builder = widget.loginBuilder;
    final loggedIn = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (context) => builder != null
            ? builder(context)
            : const LoginScreen(
                notice: 'Inicia sessió per veure el teu historial.',
              ),
      ),
    );
    if (loggedIn == true) await _load();
  }

  void _openDetail(Event event) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            EventDetailScreen(eventId: event.id, initialEvent: event),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: CaliuColors.red,
      onRefresh: _load,
      child: _buildBody(),
    );
  }

  Widget _buildBody() {
    final events = _events;

    if (_loading && events == null) {
      return const Center(
        child: CircularProgressIndicator(color: CaliuColors.red),
      );
    }

    if (_error case final error?) {
      if (error.isUnauthorized) {
        return CenteredMessage(
          icon: Icons.lock_outline,
          title: 'Inicia sessió per veure el teu historial',
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
          onPressed: _load,
          style: FilledButton.styleFrom(backgroundColor: CaliuColors.red),
          child: const Text('Tornar a provar'),
        ),
      );
    }

    if (events == null || events.isEmpty) {
      return const CenteredMessage(
        icon: Icons.event_available,
        title: 'Encara no has assistit a cap esdeveniment',
        subtitle:
            'Quan assisteixis a exposicions, fires o concerts, els trobaràs '
            'aquí per recordar-los.',
      );
    }

    final now = widget.now ?? DateTime.now();
    final groups = groupByYear(events);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        for (final MapEntry(key: year, value: yearEvents)
            in groups.entries) ...[
          _YearHeader(year: year, count: yearEvents.length),
          for (final event in yearEvents)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: EventListTile(
                key: ValueKey(event.id),
                event: event,
                subtitle: _subtitle(event, now),
                onTap: () => _openDetail(event),
              ),
            ),
        ],
      ],
    );
  }

  String _subtitle(Event event, DateTime now) {
    final parts = <String>[
      activityWhen(event.startDate!, now),
      if (event.shortPlace.isNotEmpty) event.shortPlace,
    ];
    return parts.join(' · ');
  }
}

/// Agrupa els esdeveniments per any de la data d'inici, mantenint l'ordre
/// (els anys apareixen en l'ordre en què surten a la llista).
Map<int, List<Event>> groupByYear(List<Event> events) {
  final groups = <int, List<Event>>{};
  for (final event in events) {
    final year = event.startDate?.year;
    if (year == null) continue;
    groups.putIfAbsent(year, () => []).add(event);
  }
  return groups;
}

class _YearHeader extends StatelessWidget {
  const _YearHeader({required this.year, required this.count});

  final int year;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
      child: Text(
        '$year · $count ${count == 1 ? 'esdeveniment' : 'esdeveniments'}',
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
          color: CaliuColors.maroon,
        ),
      ),
    );
  }
}
