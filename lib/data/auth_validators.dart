import 'dart:convert';

class AuthValidators {
  static final RegExp _usernameCharacters = RegExp(
    r'^[\p{L}\p{N}._-]+$',
    unicode: true,
  );
  static final RegExp _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  static String? username(String? value) {
    final candidate = value?.trim() ?? '';
    if (candidate.isEmpty) return 'El nom d’usuari és obligatori.';

    final length = candidate.runes.length;
    if (length < 3 || length > 30) {
      return 'El nom d’usuari ha de tenir entre 3 i 30 caràcters.';
    }
    if (!_usernameCharacters.hasMatch(candidate)) {
      return 'Utilitza només lletres, números, punt, guió o guió baix.';
    }
    return null;
  }

  static String? email(String? value) {
    final candidate = value?.trim() ?? '';
    if (candidate.isEmpty) return 'El correu electrònic és obligatori.';
    if (candidate.length > 254 || !_emailPattern.hasMatch(candidate)) {
      return 'Introdueix un correu electrònic vàlid.';
    }
    return null;
  }

  static String? password(String? value) {
    final candidate = value ?? '';
    if (candidate.isEmpty || candidate.trim().isEmpty) {
      return 'La contrasenya és obligatòria.';
    }
    if (candidate.runes.length < 8) {
      return 'La contrasenya ha de tenir almenys 8 caràcters.';
    }
    if (utf8.encode(candidate).length > 72) {
      return 'La contrasenya no pot superar els 72 bytes UTF-8.';
    }
    if (candidate.runes.any(
      (character) =>
          character < 0x20 || (character >= 0x7f && character <= 0x9f),
    )) {
      return 'La contrasenya no pot contenir caràcters de control.';
    }
    return null;
  }

  static String? passwordConfirmation(String? value, String password) {
    if (value != password) return 'Les contrasenyes no coincideixen.';
    return null;
  }
}
