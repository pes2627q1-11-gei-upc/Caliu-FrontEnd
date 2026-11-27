import 'dart:ui';

/// Idiomes que entén el xatbot (H.U #15).
const chatLocales = ['ca', 'es', 'en'];

/// Idioma de l'app que s'envia al xatbot (tasca #147): el primer idioma
/// preferit del dispositiu que el xatbot entén o, si no n'hi ha cap, el
/// català. El backend només el fa servir quan no pot detectar l'idioma del
/// missatge (p. ex. "ok" o "Girona").
///
/// Quan l'app tingui selector d'idioma, aquí s'haurà de llegir aquell valor.
String appChatLocale([List<Locale>? preferred]) {
  for (final locale in preferred ?? PlatformDispatcher.instance.locales) {
    final code = locale.languageCode.toLowerCase();
    if (chatLocales.contains(code)) return code;
  }
  return chatLocales.first;
}
