import 'package:flutter/material.dart';

import 'data/activity_api.dart';
import 'data/event.dart';
import 'event_detail_screen.dart';
import 'login_screen.dart';
import 'theme/caliu_colors.dart';
import 'widgets/centered_message.dart';

/// Historial d'assistència de l'usuari, per a la pestanya Activitat del
/// perfil (tasca #152, H.U #36). Separa les assistències dels darrers
/// [recentMonths] mesos de les anteriors. Es carrega en mostrar-se i estirant
/// cap avall.
class ActivityList extends StatefulWidget {
  const ActivityList({
    super.key,
    this.api,
    this.now,
    this.loginBuilder,
    this.recentMonths = defaultRecentMonths,
  });

  /// Mesos que compten com a "recents". La H.U #36 el deixa a confirmar per
  /// l'equip: de moment, 3.
  static const defaultRecentMonths = 3;

  final int recentMonths;

  /// Per defecte, [createActivityApi].
  final ActivityApi? api;

  /// Per als tests; per defecte, `DateTime.now()`.
  final DateTime? now;

  /// Per als tests; per defecte, la pantalla de login de l'app.
  final WidgetBuilder? loginBuilder;

  @override
  State<ActivityList> createState() => _ActivityListState();
}

class _ActivityListState extends State<ActivityList> {
  late final ActivityApi _api = widget.api ?? createActivityApi();

  List<ActivityEntry>? _entries;
  ActivityApiException? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final entries = await _api.fetchActivity();
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _error = null;
        _loading = false;
      });
    } on ActivityApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _entries = null;
        _error = e;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _entries = null;
        _error = const ActivityApiException(
          'No s\'ha pogut carregar l\'activitat',
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
                notice: 'Inicia sessió per veure la teva activitat.',
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
    final entries = _entries;

    if (_loading && entries == null) {
      return const Center(
        child: CircularProgressIndicator(color: CaliuColors.red),
      );
    }

    if (_error case final error?) {
      if (error.isUnauthorized) {
        return CenteredMessage(
          icon: Icons.lock_outline,
          title: 'Inicia sessió per veure la teva activitat',
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

    if (entries == null || entries.isEmpty) {
      return const CenteredMessage(
        icon: Icons.history,
        title: 'Encara no hi ha activitat',
        subtitle: 'Aquí veuràs els esdeveniments als quals assisteixis.',
      );
    }

    final now = widget.now ?? DateTime.now();
    final (recent, older) = splitActivity(entries, now, widget.recentMonths);
    final months = widget.recentMonths;
    final recentTitle = months == 1 ? 'Darrer mes' : 'Darrers $months mesos';

    Widget tile(ActivityEntry entry) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _ActivityTile(
        key: ValueKey(entry.id),
        entry: entry,
        when: activityWhen(entry.at, now),
        onTap: () => _openDetail(entry.event),
      ),
    );

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        _SectionHeader(title: recentTitle, count: recent.length),
        if (recent.isEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: Text(
              'Cap assistència en aquest període.',
              style: TextStyle(color: CaliuColors.textMuted),
            ),
          ),
        ...recent.map(tile),
        if (older.isNotEmpty) ...[
          _SectionHeader(title: 'Anteriors', count: older.length),
          ...older.map(tile),
        ],
      ],
    );
  }
}

/// Separa les assistències en recents (dins dels darrers [months] mesos
/// respecte a [now]) i anteriors, mantenint l'ordre.
(List<ActivityEntry>, List<ActivityEntry>) splitActivity(
  List<ActivityEntry> entries,
  DateTime now,
  int months,
) {
  final limit = DateTime(now.year, now.month - months, now.day);
  final recent = <ActivityEntry>[];
  final older = <ActivityEntry>[];
  for (final entry in entries) {
    (entry.at.isBefore(limit) ? older : recent).add(entry);
  }
  return (recent, older);
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
      child: Text(
        '${title.toUpperCase()} · $count',
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

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({
    super.key,
    required this.entry,
    required this.when,
    required this.onTap,
  });

  final ActivityEntry entry;
  final String when;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final place = entry.event.shortPlace;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: CaliuColors.red.withValues(alpha: 0.12),
                foregroundColor: CaliuColors.red,
                child: const Icon(Icons.check_circle, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Has assistit a · $when',
                      style: const TextStyle(
                        color: CaliuColors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      entry.event.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: CaliuColors.maroonDeep,
                      ),
                    ),
                    if (place.isNotEmpty)
                      Text(
                        place,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: CaliuColors.textMuted,
                          fontSize: 13,
                        ),
                      ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: CaliuColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

const _months = [
  'gen.',
  'febr.',
  'març',
  'abr.',
  'maig',
  'juny',
  'jul.',
  'ag.',
  'set.',
  'oct.',
  'nov.',
  'des.',
];

/// Data relativa curta: "avui", "ahir", "fa 3 dies" o "12 de nov.".
String activityWhen(DateTime at, DateTime now) {
  final day = DateTime(at.year, at.month, at.day);
  final today = DateTime(now.year, now.month, now.day);
  final days = today.difference(day).inDays;
  if (days <= 0) return 'avui';
  if (days == 1) return 'ahir';
  if (days < 7) return 'fa $days dies';
  final month = _months[at.month - 1];
  final sep = month.startsWith(RegExp('[aeiou]')) ? 'd\'' : 'de ';
  final date = '${at.day} $sep$month';
  return at.year == now.year ? date : '$date ${at.year}';
}
