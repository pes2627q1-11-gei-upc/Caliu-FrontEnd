/// Filtres ràpids de data per a la cerca (US5): Avui, Demà i Cap de setmana.
///
/// El càlcul és lògica pura: rep `now` per paràmetre perquè es pugui testejar
/// amb dates fixes. Les dates es calculen en hora local del dispositiu i
/// [EventQuery] les envia a l'API convertides a UTC.
enum DateRangeFilter {
  today('Avui'),
  tomorrow('Demà'),
  weekend('Cap de setmana');

  const DateRangeFilter(this.label);

  final String label;

  /// Interval [from, to] (tots dos inclosos) que correspon al filtre.
  DateRange rangeFor(DateTime now) {
    switch (this) {
      case DateRangeFilter.today:
        return DateRange(now, _endOfDay(now));
      case DateRangeFilter.tomorrow:
        final tomorrow = DateTime(now.year, now.month, now.day + 1);
        return DateRange(tomorrow, _endOfDay(tomorrow));
      case DateRangeFilter.weekend:
        if (now.weekday == DateTime.sunday) {
          return DateRange(now, _endOfDay(now));
        }
        if (now.weekday == DateTime.saturday) {
          final sunday = DateTime(now.year, now.month, now.day + 1);
          return DateRange(now, _endOfDay(sunday));
        }
        final daysToSaturday = DateTime.saturday - now.weekday;
        final saturday = DateTime(now.year, now.month, now.day + daysToSaturday);
        final sunday = DateTime(saturday.year, saturday.month, saturday.day + 1);
        return DateRange(saturday, _endOfDay(sunday));
    }
  }

  static DateTime _endOfDay(DateTime day) =>
      DateTime(day.year, day.month, day.day, 23, 59, 59, 999);
}

class DateRange {
  const DateRange(this.from, this.to);

  final DateTime from;
  final DateTime to;

  @override
  bool operator ==(Object other) =>
      other is DateRange && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);

  @override
  String toString() => 'DateRange($from → $to)';
}
