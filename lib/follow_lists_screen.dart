import 'package:flutter/material.dart';

import 'data/users_api.dart';
import 'public_profile_screen.dart';
import 'theme/caliu_colors.dart';
import 'widgets/user_avatar.dart';

/// Quina llista s'obre primer a [FollowListsScreen].
enum FollowList { followers, following }

/// Llistes navegables de seguidors i seguits d'un usuari, amb el recompte de
/// cadascuna (tasca #184, H.U #62). Tocar un usuari obre el seu perfil
/// públic.
class FollowListsScreen extends StatefulWidget {
  const FollowListsScreen({
    super.key,
    required this.userId,
    required this.title,
    this.initialList = FollowList.followers,
    this.api,
  });

  final String userId;

  /// Títol de la barra: el nick o, al propi perfil, "El meu perfil".
  final String title;
  final FollowList initialList;

  /// Per defecte, [createUsersApi].
  final UsersApi? api;

  @override
  State<FollowListsScreen> createState() => _FollowListsScreenState();
}

class _FollowListsScreenState extends State<FollowListsScreen> {
  late final UsersApi _api = widget.api ?? createUsersApi();

  List<PublicUser>? _followers;
  List<PublicUser>? _following;
  UsersApiException? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final results = await Future.wait([
        _api.fetchFollowers(widget.userId),
        _api.fetchFollowing(widget.userId),
      ]);
      if (!mounted) return;
      setState(() {
        _followers = results[0];
        _following = results[1];
      });
    } on UsersApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _error = const UsersApiException(
          'No s\'han pogut carregar les llistes',
        ),
      );
    }
  }

  Future<void> _openProfile(PublicUser user) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PublicProfileScreen(
          username: user.username,
          initialUser: user,
          api: widget.api,
        ),
      ),
    );
    // En tornar, potser l'han seguit o deixat de seguir: refresca.
    if (mounted) await _load();
  }

  static String _tabLabel(String label, List<PublicUser>? users) =>
      users == null ? label : '$label · ${users.length}';

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      initialIndex: widget.initialList.index,
      child: Scaffold(
        backgroundColor: CaliuColors.beige,
        appBar: AppBar(
          backgroundColor: CaliuColors.maroonDeep,
          foregroundColor: Colors.white,
          title: Text(widget.title),
          bottom: TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: CaliuColors.redSoft,
            tabs: [
              Tab(text: _tabLabel('Seguidors', _followers)),
              Tab(text: _tabLabel('Seguits', _following)),
            ],
          ),
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    final error = _error;
    if (error != null) {
      return _Message(
        icon: error.isNotFound ? Icons.person_off_outlined : Icons.cloud_off,
        title: error.message,
        action: error.isNotFound
            ? null
            : FilledButton(
                onPressed: _load,
                style: FilledButton.styleFrom(backgroundColor: CaliuColors.red),
                child: const Text('Tornar a provar'),
              ),
      );
    }

    final followers = _followers;
    final following = _following;
    if (followers == null || following == null) {
      return const Center(
        child: CircularProgressIndicator(color: CaliuColors.red),
      );
    }

    return TabBarView(
      children: [
        _UserList(
          users: followers,
          emptyText: 'Encara no té seguidors',
          onRefresh: _load,
          onTap: _openProfile,
        ),
        _UserList(
          users: following,
          emptyText: 'Encara no segueix ningú',
          onRefresh: _load,
          onTap: _openProfile,
        ),
      ],
    );
  }
}

class _UserList extends StatelessWidget {
  const _UserList({
    required this.users,
    required this.emptyText,
    required this.onRefresh,
    required this.onTap,
  });

  final List<PublicUser> users;
  final String emptyText;
  final Future<void> Function() onRefresh;
  final ValueChanged<PublicUser> onTap;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: CaliuColors.red,
      onRefresh: onRefresh,
      child: users.isEmpty
          ? LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: SizedBox(
                  height: constraints.maxHeight,
                  child: _Message(icon: Icons.group_outlined, title: emptyText),
                ),
              ),
            )
          : ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: users.length,
              separatorBuilder: (context, index) =>
                  const Divider(height: 1, indent: 72),
              itemBuilder: (context, index) {
                final user = users[index];
                return ListTile(
                  key: ValueKey(user.id),
                  leading: UserAvatar(
                    username: user.username,
                    avatarUrl: user.avatarUrl,
                    // La fila sencera obre el perfil (i refresca en tornar).
                    openProfileOnTap: false,
                  ),
                  title: Text(
                    user.username,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: CaliuColors.maroonDeep,
                    ),
                  ),
                  subtitle: user.isFollowing
                      ? const Text('El segueixes')
                      : null,
                  trailing: const Icon(
                    Icons.chevron_right,
                    color: CaliuColors.textMuted,
                  ),
                  onTap: () => onTap(user),
                );
              },
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
