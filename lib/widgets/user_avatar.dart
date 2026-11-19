import 'package:flutter/material.dart';

import '../data/users_api.dart';
import '../public_profile_screen.dart';
import '../theme/caliu_colors.dart';

/// Foto d'un usuari. En tocar-la s'obre el seu perfil públic (H.U #60).
///
/// Es pot fer servir allà on surtin altres usuaris (grups d'esdeveniment,
/// llistes de seguidors…). Si no té foto, mostra la inicial del nick.
class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.username,
    this.avatarUrl,
    this.radius = 20,
    this.openProfileOnTap = true,
    this.api,
  });

  final String username;
  final String? avatarUrl;
  final double radius;

  /// Si és cert, tocar l'avatar obre [PublicProfileScreen].
  final bool openProfileOnTap;

  /// Per als tests; es passa a la pantalla de perfil públic.
  final UsersApi? api;

  @override
  Widget build(BuildContext context) {
    final url = avatarUrl;
    final initial = username.trim().isEmpty
        ? '?'
        : username.trim()[0].toUpperCase();
    final avatar = CircleAvatar(
      radius: radius,
      backgroundColor: CaliuColors.maroon,
      foregroundColor: Colors.white,
      foregroundImage: url != null ? NetworkImage(url) : null,
      onForegroundImageError: url != null ? (_, _) {} : null,
      child: Text(
        initial,
        style: TextStyle(fontSize: radius * 0.8, fontWeight: FontWeight.w700),
      ),
    );
    if (!openProfileOnTap) return avatar;

    return Semantics(
      button: true,
      label: 'Veure el perfil de $username',
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => PublicProfileScreen(
              username: username,
              initialUser: PublicUser(
                id: '',
                username: username,
                avatarUrl: avatarUrl,
              ),
              api: api,
            ),
          ),
        ),
        child: avatar,
      ),
    );
  }
}
