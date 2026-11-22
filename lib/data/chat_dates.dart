/// Textos de dates curts per al xat (filtres interpretats i itineraris).
///
/// Lògica pura: rep `now` per poder-la testejar amb dates fixes.
library;

/// "Avui", "Demà" o "Dissabte 22 de novembre".
String chatDayLabel(DateTime date, DateTime now) {
  final day = DateTime(date.year, date.month, date.day);
  final today = DateTime(now.year, now.month, now.day);
  if (day == today) return 'Avui';
  if (day == DateTime(now.year, now.month, now.day + 1)) return 'Demà';
  return '${_weekdays[date.weekday - 1]} ${chatDayMonth(date)}';
}

/// "22 de novembre", "3 d'abril".
String chatDayMonth(DateTime date) {
  final month = _months[date.month - 1];
  final prep = 'aeiou'.contains(month[0]) ? "d'" : 'de ';
  return '${date.day} $prep$month';
}

/// "18:30".
String chatTime(DateTime date) {
  final hh = date.hour.toString().padLeft(2, '0');
  final mm = date.minute.toString().padLeft(2, '0');
  return '$hh:$mm';
}

const _weekdays = [
  'Dilluns',
  'Dimarts',
  'Dimecres',
  'Dijous',
  'Divendres',
  'Dissabte',
  'Diumenge',
];

const _months = [
  'gener',
  'febrer',
  'març',
  'abril',
  'maig',
  'juny',
  'juliol',
  'agost',
  'setembre',
  'octubre',
  'novembre',
  'desembre',
];
