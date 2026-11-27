import 'package:flutter/material.dart';

import '../login_screen.dart';
import '../theme/caliu_colors.dart';

/// Missatge que veu l'usuari a la pantalla de login quan hi arriba des d'un cor.
const favoritesLoginNotice = 'Inicia sessió per guardar els teus preferits.';

/// Pantalla de login que s'obre des dels preferits. Els tests en posen una
/// de falsa per no dependre de l'API d'autenticació.
typedef FavoritesLoginBuilder = WidgetBuilder;

Widget _defaultLoginBuilder(BuildContext context) =>
    const LoginScreen(notice: favoritesLoginNotice);

/// Explica que cal sessió per gestionar preferits i, si l'usuari accepta,
/// obre el login (tasca #191). Retorna `true` si ha iniciat sessió.
Future<bool> requestFavoritesLogin(
  BuildContext context, {
  FavoritesLoginBuilder? loginBuilder,
}) async {
  final navigator = Navigator.of(context);
  final wantsLogin = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: const Icon(Icons.favorite, color: CaliuColors.red),
      title: const Text('Guarda els teus preferits'),
      content: const Text(
        'Inicia sessió per guardar esdeveniments a Preferits i trobar-los '
        'des de qualsevol dispositiu.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Ara no'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          style: FilledButton.styleFrom(backgroundColor: CaliuColors.red),
          child: const Text('Inicia sessió'),
        ),
      ],
    ),
  );
  if (wantsLogin != true) return false;

  final loggedIn = await navigator.push<bool>(
    MaterialPageRoute<bool>(builder: loginBuilder ?? _defaultLoginBuilder),
  );
  return loggedIn == true;
}
