import 'package:flutter/material.dart';

import 'data/activity_api.dart';
import 'data/event.dart';
import 'event_detail_screen.dart';
import 'login_screen.dart';
import 'theme/caliu_colors.dart';
import 'widgets/centered_message.dart';

/// Historial d'activitat de l'usuari, per a la pestanya Activitat del perfil
/// (tasca #152, H.U #36). Es carrega en mostrar-se i estirant cap avall.
class ActivityList extends StatefulWidget {
  const ActivityList({super.key, this.api, this.now, this.loginBuilder});

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
        subtitle:
            'Aquí veuràs els esdeveniments que afegeixis a preferits i '
            'als quals assisteixis.',
      );
    }

    final now = widget.now ?? DateTime.now();
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      itemCount: entries.length,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final entry = entries[index];
        return _ActivityTile(
          key: ValueKey(entry.id),
          entry: entry,
          when: activityWhen(entry.at, now),
          onTap: () => _openDetail(entry.event),
        );
      },
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
    final (icon, label) = switch (entry.type) {
      ActivityType.favoriteAdded => (Icons.favorite, 'Has afegit a preferits'),
      ActivityType.attended => (Icons.check_circle, 'Has assistit a'),
    };
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
                child: Icon(icon, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$label · $when',
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
