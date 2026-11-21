import 'package:flutter/material.dart';

import 'data/users_api.dart';
import 'follow_lists_screen.dart';
import 'login_screen.dart';
import 'theme/caliu_colors.dart';
import 'widgets/user_avatar.dart';

/// Perfil públic d'un altre usuari (tasca #179, H.U #60): avatar, nick i
/// recompte d'actes compartits, amb el botó Seguir (tasca #182, H.U #61).
/// No mostra cap dada privada com l'email.
class PublicProfileScreen extends StatefulWidget {
  const PublicProfileScreen({
    super.key,
    required this.username,
    this.initialUser,
    this.api,
    this.loginBuilder,
  });

  final String username;

  /// Dades que ja es tenen (p. ex. de la llista on s'ha tocat l'avatar), per
  /// mostrar alguna cosa mentre es carrega el perfil.
  final PublicUser? initialUser;

  /// Per defecte, [createUsersApi].
  final UsersApi? api;

  /// Per als tests; per defecte, la pantalla de login de l'app.
  final WidgetBuilder? loginBuilder;

  @override
  State<PublicProfileScreen> createState() => _PublicProfileScreenState();
}

class _PublicProfileScreenState extends State<PublicProfileScreen> {
  late final UsersApi _api = widget.api ?? createUsersApi();

  late PublicUser? _user = widget.initialUser;
  UsersApiException? _error;
  bool _loading = true;

  /// Les dades de [widget.initialUser] no porten el recompte: només es
  /// mostra quan arriba el perfil del servidor.
  bool _fetched = false;

  /// Hi ha una petició de seguir / deixar de seguir en curs.
  bool _followPending = false;

  /// Recomptes de seguidors i seguits (H.U #62). Null mentre es carreguen o
  /// si no s'han pogut carregar.
  int? _followersCount;
  int? _followingCount;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final user = await _api.fetchPublicProfile(widget.username);
      if (!mounted) return;
      setState(() {
        _user = user;
        _fetched = true;
        _loading = false;
      });
      await _loadCounts(user.id);
    } on UsersApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = const UsersApiException('No s\'ha pogut carregar el perfil');
        _loading = false;
      });
    }
  }

  /// El recompte es calcula a partir de les llistes, perquè coincideixi
  /// sempre amb el nombre d'elements que es veuran en obrir-les.
  Future<void> _loadCounts(String userId) async {
    try {
      final results = await Future.wait([
        _api.fetchFollowers(userId),
        _api.fetchFollowing(userId),
      ]);
      if (!mounted) return;
      setState(() {
        _followersCount = results[0].length;
        _followingCount = results[1].length;
      });
    } catch (_) {
      // Els recomptes són secundaris: si fallen, no es mostren.
    }
  }

  Future<void> _openFollowLists(FollowList list) async {
    final user = _user;
    if (user == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FollowListsScreen(
          userId: user.id,
          title: '@${user.username}',
          initialList: list,
          api: widget.api,
        ),
      ),
    );
    if (mounted) await _load();
  }

  /// Seguir o deixar de seguir, amb canvi optimista: el botó canvia a
  /// l'instant i, si la petició falla, torna a l'estat anterior.
  Future<void> _toggleFollow() async {
    final user = _user;
    if (user == null || _followPending) return;
    final messenger = ScaffoldMessenger.of(context);
    final wasFollowing = user.isFollowing;
    setState(() {
      _followPending = true;
      _user = user.copyWith(isFollowing: !wasFollowing);
      // Jo passo a ser (o deixo de ser) un dels seus seguidors.
      if (_followersCount case final count?) {
        _followersCount = count + (wasFollowing ? -1 : 1);
      }
    });
    try {
      if (wasFollowing) {
        await _api.unfollow(user.id);
      } else {
        await _api.follow(user.id);
      }
      if (!mounted) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              wasFollowing
                  ? 'Has deixat de seguir ${user.username}'
                  : 'Ara segueixes ${user.username}',
            ),
          ),
        );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _user = _user?.copyWith(isFollowing: wasFollowing);
        if (_followersCount case final count?) {
          _followersCount = count + (wasFollowing ? 1 : -1);
        }
      });
      final message = e is UsersApiException
          ? e.message
          : 'No s\'ha pogut actualitzar el seguiment';
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _followPending = false);
    }
  }

  Future<void> _login() async {
    final builder = widget.loginBuilder;
    final loggedIn = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (context) => builder != null
            ? builder(context)
            : const LoginScreen(
                notice: 'Inicia sessió per veure perfils d\'altres usuaris.',
              ),
      ),
    );
    if (loggedIn == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CaliuColors.beige,
      appBar: AppBar(
        backgroundColor: CaliuColors.maroonDeep,
        foregroundColor: Colors.white,
        title: Text('@${widget.username}'),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    final error = _error;
    if (error != null) {
      if (error.isUnauthorized) {
        return _Message(
          icon: Icons.lock_outline,
          title: 'Inicia sessió per veure perfils d\'altres usuaris',
          action: FilledButton.icon(
            onPressed: _login,
            icon: const Icon(Icons.login),
            label: const Text('Inicia sessió'),
            style: FilledButton.styleFrom(backgroundColor: CaliuColors.red),
          ),
        );
      }
      if (error.isNotFound) {
        return _Message(
          icon: Icons.person_off_outlined,
          title: 'Aquest usuari no existeix',
          subtitle:
              'Potser ha canviat de nom o ha eliminat el compte. '
              'Comprova l\'enllaç i torna-ho a provar.',
        );
      }
      return _Message(
        icon: Icons.cloud_off,
        title: error.message,
        action: FilledButton(
          onPressed: _load,
          style: FilledButton.styleFrom(backgroundColor: CaliuColors.red),
          child: const Text('Tornar a provar'),
        ),
      );
    }

    final user = _user;
    if (user == null) {
      return const Center(
        child: CircularProgressIndicator(color: CaliuColors.red),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 32, 20, 24),
      children: [
        if (_loading)
          const Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: LinearProgressIndicator(
              color: CaliuColors.red,
              backgroundColor: CaliuColors.beige,
            ),
          ),
        Center(
          child: UserAvatar(
            username: user.username,
            avatarUrl: user.avatarUrl,
            radius: 56,
            // Ja som al seu perfil: tocar l'avatar no ha de tornar a obrir-lo.
            openProfileOnTap: false,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          user.username,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: CaliuColors.maroonDeep,
          ),
        ),
        if (_fetched) ...[
          const SizedBox(height: 16),
          Center(
            child: _FollowButton(
              following: user.isFollowing,
              pending: _followPending,
              onPressed: _toggleFollow,
            ),
          ),
          if (_followersCount != null && _followingCount != null) ...[
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _CountButton(
                  key: const Key('followers-count'),
                  count: _followersCount!,
                  label: _followersCount == 1 ? 'seguidor' : 'seguidors',
                  onTap: () => _openFollowLists(FollowList.followers),
                ),
                const SizedBox(width: 24),
                _CountButton(
                  key: const Key('following-count'),
                  count: _followingCount!,
                  label: _followingCount == 1 ? 'seguit' : 'seguits',
                  onTap: () => _openFollowLists(FollowList.following),
                ),
              ],
            ),
          ],
        ],
        const SizedBox(height: 24),
        if (_fetched)
          Card(
            color: CaliuColors.beigeCard,
            elevation: 0,
            child: ListTile(
              leading: const CircleAvatar(
                backgroundColor: CaliuColors.maroon,
                foregroundColor: Colors.white,
                child: Icon(Icons.event_available),
              ),
              title: Text(
                sharedEventsLabel(user.sharedEventsCount),
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: CaliuColors.maroonDeep,
                ),
              ),
              subtitle: const Text('Esdeveniments als quals heu anat tots dos'),
            ),
          ),
      ],
    );
  }
}

/// "Seguir" (ple) o "Seguint" (contornejat). Tornar-lo a tocar deixa de
/// seguir.
class _FollowButton extends StatelessWidget {
  const _FollowButton({
    required this.following,
    required this.pending,
    required this.onPressed,
  });

  final bool following;
  final bool pending;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final onTap = pending ? null : onPressed;
    if (following) {
      return OutlinedButton.icon(
        key: const Key('follow-button'),
        onPressed: onTap,
        icon: const Icon(Icons.check),
        label: const Text('Seguint'),
        style: OutlinedButton.styleFrom(
          foregroundColor: CaliuColors.maroon,
          side: const BorderSide(color: CaliuColors.maroon),
          minimumSize: const Size(160, 44),
        ),
      );
    }
    return FilledButton.icon(
      key: const Key('follow-button'),
      onPressed: onTap,
      icon: const Icon(Icons.person_add_alt_1),
      label: const Text('Seguir'),
      style: FilledButton.styleFrom(
        backgroundColor: CaliuColors.red,
        minimumSize: const Size(160, 44),
      ),
    );
  }
}

/// Recompte tocable ("3 seguidors") que obre la llista corresponent.
class _CountButton extends StatelessWidget {
  const _CountButton({
    super.key,
    required this.count,
    required this.label,
    required this.onTap,
  });

  final int count;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(
          children: [
            Text(
              '$count',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: CaliuColors.maroonDeep,
              ),
            ),
            Text(label, style: const TextStyle(color: CaliuColors.textMuted)),
          ],
        ),
      ),
    );
  }
}

/// "Cap acte compartit", "1 acte compartit" o "N actes compartits".
String sharedEventsLabel(int count) => switch (count) {
  <= 0 => 'Cap acte compartit',
  1 => '1 acte compartit',
  _ => '$count actes compartits',
};

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
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
            if (subtitle case final subtitle?) ...[
              const SizedBox(height: 8),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(color: CaliuColors.textMuted),
              ),
            ],
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
