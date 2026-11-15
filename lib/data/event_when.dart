import 'event.dart';

/// Text curt de "quan" per a la previsualització del mapa (H.U #44).
///
/// Exemples: "Avui · 19:30 h", "Demà", "Dissabte 21 de novembre · 18:00 h",
/// "Fins al 20 de desembre" (esdeveniment de diversos dies que ja ha començat).
/// És lògica pura: rep `now` per poder-la testejar amb dates fixes.
String previewWhen(Event event, DateTime now) {
  final start = event.startDate?.toLocal();
  if (start == null) return 'Data per confirmar';
  final end = event.endDate?.toLocal() ?? start;

  final today = DateTime(now.year, now.month, now.day);
  final tomorrow = DateTime(now.year, now.month, now.day + 1);
  final startDay = DateTime(start.year, start.month, start.day);

  // Exposicions i similars: van començar fa dies i encara duren.
  if (startDay.isBefore(today) && !end.isBefore(now)) {
    return 'Fins al ${_dayMonth(end)}';
  }

  final String day;
  if (startDay == today) {
    day = 'Avui';
  } else if (startDay == tomorrow) {
    day = 'Demà';
  } else {
    day = '${_weekdays[start.weekday - 1]} ${_dayMonth(start)}';
  }

  // La font sol posar les 00:00 quan l'hora real només és al text de l'horari.
  final hasTime = start.hour != 0 || start.minute != 0;
  if (!hasTime) return day;
  final hh = start.hour.toString().padLeft(2, '0');
  final mm = start.minute.toString().padLeft(2, '0');
  return '$day · $hh:$mm h';
}

String _dayMonth(DateTime date) {
  final month = _months[date.month - 1];
  // "d'abril", "d'agost", "d'octubre"; "de novembre"...
  final prep = 'aeiou'.contains(month[0]) ? "d'" : 'de ';
  return '${date.day} $prep$month';
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
