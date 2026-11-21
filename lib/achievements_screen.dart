import 'package:flutter/material.dart';

import 'data/achievements_api.dart';
import 'login_screen.dart';
import 'theme/caliu_colors.dart';

/// Catàleg complet d'assoliments amb el progrés de l'usuari (tasca #177,
/// H.U #59): recompte, medalles amb barra de progrés i, en gris, les que
/// encara no s'han desbloquejat.
class AchievementsScreen extends StatefulWidget {
  const AchievementsScreen({super.key, this.api, this.loginBuilder});

  /// Per defecte, [createAchievementsApi].
  final AchievementsApi? api;

  /// Per als tests; per defecte, la pantalla de login de l'app.
  final WidgetBuilder? loginBuilder;

  @override
  State<AchievementsScreen> createState() => _AchievementsScreenState();
}

class _AchievementsScreenState extends State<AchievementsScreen> {
  late final AchievementsApi _api = widget.api ?? createAchievementsApi();

  List<Achievement>? _achievements;
  AchievementsApiException? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final achievements = await _api.fetchAchievements();
      if (!mounted) return;
      setState(() => _achievements = achievements);
    } on AchievementsApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _error = const AchievementsApiException(
          'No s\'han pogut carregar els assoliments',
        ),
      );
    }
  }

  Future<void> _login() async {
    final builder = widget.loginBuilder;
    final loggedIn = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (context) => builder != null
            ? builder(context)
            : const LoginScreen(
                notice: 'Inicia sessió per veure els teus assoliments.',
              ),
      ),
    );
    if (loggedIn == true) await _load();
  }

  void _showDetail(Achievement achievement) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: CaliuColors.beigeCard,
      builder: (context) => _AchievementDetail(achievement: achievement),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CaliuColors.beige,
      appBar: AppBar(
        backgroundColor: CaliuColors.maroonDeep,
        foregroundColor: Colors.white,
        title: const Text('Assoliments'),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    final error = _error;
    if (error != null) {
      return _Message(
        icon: error.isUnauthorized ? Icons.lock_outline : Icons.cloud_off,
        title: error.isUnauthorized
            ? 'Inicia sessió per veure els teus assoliments'
            : error.message,
        action: error.isUnauthorized
            ? FilledButton.icon(
                onPressed: _login,
                icon: const Icon(Icons.login),
                label: const Text('Inicia sessió'),
                style: FilledButton.styleFrom(backgroundColor: CaliuColors.red),
              )
            : FilledButton(
                onPressed: _load,
                style: FilledButton.styleFrom(backgroundColor: CaliuColors.red),
                child: const Text('Tornar a provar'),
              ),
      );
    }

    final achievements = _achievements;
    if (achievements == null) {
      return const Center(
        child: CircularProgressIndicator(color: CaliuColors.red),
      );
    }
    if (achievements.isEmpty) {
      return const _Message(
        icon: Icons.emoji_events_outlined,
        title: 'Encara no hi ha assoliments disponibles',
      );
    }

    final unlocked = achievements.where((a) => a.unlocked).length;
    return RefreshIndicator(
      color: CaliuColors.red,
      onRefresh: _load,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: _Summary(unlocked: unlocked, total: achievements.length),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            sliver: SliverGrid.builder(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 220,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.78,
              ),
              itemCount: achievements.length,
              itemBuilder: (context, index) {
                final achievement = achievements[index];
                return _MedalCard(
                  key: ValueKey(achievement.id),
                  achievement: achievement,
                  onTap: () => _showDetail(achievement),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Icona de cada medalla segons la clau que envia el servidor.
IconData achievementIcon(String key) => switch (key) {
  'steps' => Icons.directions_walk,
  'explore' => Icons.explore,
  'museum' => Icons.museum,
  'fair' => Icons.storefront,
  'favorite' => Icons.favorite,
  'people' => Icons.groups,
  _ => Icons.emoji_events,
};

/// "3/5" o, si ja està desbloquejada, "Aconseguida".
String achievementProgressLabel(Achievement achievement) => achievement.unlocked
    ? 'Aconseguida'
    : '${achievement.progress}/${achievement.target}';

class _Summary extends StatelessWidget {
  const _Summary({required this.unlocked, required this.total});

  final int unlocked;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Card(
        color: CaliuColors.maroon,
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$unlocked de $total medalles',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                unlocked == total
                    ? 'Has completat la col·lecció!'
                    : 'Continua participant per completar la col·lecció.',
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  key: const Key('collection-progress'),
                  value: total == 0 ? 0 : unlocked / total,
                  minHeight: 8,
                  color: CaliuColors.redSoft,
                  backgroundColor: Colors.white24,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MedalCard extends StatelessWidget {
  const _MedalCard({super.key, required this.achievement, required this.onTap});

  final Achievement achievement;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final unlocked = achievement.unlocked;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Medal(achievement: achievement, radius: 34),
              const SizedBox(height: 10),
              Text(
                achievement.title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: unlocked
                      ? CaliuColors.maroonDeep
                      : CaliuColors.textMuted,
                ),
              ),
              const Spacer(),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: achievement.fraction,
                  minHeight: 6,
                  color: unlocked ? CaliuColors.red : Colors.grey,
                  backgroundColor: Colors.grey.shade200,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                achievementProgressLabel(achievement),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: unlocked ? CaliuColors.red : CaliuColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Medalla circular: de color si està desbloquejada, en gris si no.
class Medal extends StatelessWidget {
  const Medal({super.key, required this.achievement, this.radius = 30});

  final Achievement achievement;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final unlocked = achievement.unlocked;
    return Semantics(
      label: unlocked ? 'Medalla aconseguida' : 'Medalla bloquejada',
      child: CircleAvatar(
        radius: radius,
        backgroundColor: unlocked ? CaliuColors.red : Colors.grey.shade300,
        foregroundColor: unlocked ? Colors.white : Colors.grey.shade600,
        child: Icon(achievementIcon(achievement.icon), size: radius),
      ),
    );
  }
}

class _AchievementDetail extends StatelessWidget {
  const _AchievementDetail({required this.achievement});

  final Achievement achievement;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Medal(achievement: achievement, radius: 44),
            const SizedBox(height: 16),
            Text(
              achievement.title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: CaliuColors.maroonDeep,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              achievement.description,
              textAlign: TextAlign.center,
              style: const TextStyle(color: CaliuColors.textMuted),
            ),
            const SizedBox(height: 16),
            Text(
              achievement.unlocked
                  ? 'Aconseguida!'
                  : 'Progrés: ${achievement.progress} de ${achievement.target}',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: CaliuColors.red,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.title, this.action});

  final IconData icon;
  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
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
            if (action case final action?) ...[
              const SizedBox(height: 20),
              action,
            ],
          ],
        ),
      ),
    );
  }
}
