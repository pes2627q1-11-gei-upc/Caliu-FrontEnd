import 'package:caliu/data/date_range_filter.dart';
import 'package:caliu/data/event_query.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Dimecres 11/11/2026 a les 17:30
  final wednesday = DateTime(2026, 11, 11, 17, 30);
  final saturday = DateTime(2026, 11, 14, 10, 0);
  final sunday = DateTime(2026, 11, 15, 20, 15);

  DateTime endOf(int y, int m, int d) => DateTime(y, m, d, 23, 59, 59, 999);

  group('DateRangeFilter.today', () {
    test('va de ara fins al final del dia', () {
      expect(
        DateRangeFilter.today.rangeFor(wednesday),
        DateRange(wednesday, endOf(2026, 11, 11)),
      );
    });
  });

  group('DateRangeFilter.tomorrow', () {
    test('cobreix tot el dia següent', () {
      expect(
        DateRangeFilter.tomorrow.rangeFor(wednesday),
        DateRange(DateTime(2026, 11, 12), endOf(2026, 11, 12)),
      );
    });

    test('canvia de mes i d\'any correctament', () {
      expect(
        DateRangeFilter.tomorrow.rangeFor(DateTime(2026, 12, 31, 22)),
        DateRange(DateTime(2027, 1, 1), endOf(2027, 1, 1)),
      );
    });
  });

  group('DateRangeFilter.weekend', () {
    test('entre setmana: de dissabte 00:00 a diumenge 23:59', () {
      expect(
        DateRangeFilter.weekend.rangeFor(wednesday),
        DateRange(DateTime(2026, 11, 14), endOf(2026, 11, 15)),
      );
    });

    test('divendres: el cap de setmana és l\'endemà', () {
      expect(
        DateRangeFilter.weekend.rangeFor(DateTime(2026, 11, 13, 23)),
        DateRange(DateTime(2026, 11, 14), endOf(2026, 11, 15)),
      );
    });

    test('dissabte: des d\'ara fins diumenge', () {
      expect(
        DateRangeFilter.weekend.rangeFor(saturday),
        DateRange(saturday, endOf(2026, 11, 15)),
      );
    });

    test('diumenge: des d\'ara fins al final del dia', () {
      expect(
        DateRangeFilter.weekend.rangeFor(sunday),
        DateRange(sunday, endOf(2026, 11, 15)),
      );
    });
  });

  group('EventQuery amb dates', () {
    test('envia from/to en UTC i ISO 8601', () {
      final range = DateRangeFilter.tomorrow.rangeFor(wednesday);
      final params =
          EventQuery(from: range.from, to: range.to).toQueryParameters();
      expect(params['from'], range.from.toUtc().toIso8601String());
      expect(params['to'], range.to.toUtc().toIso8601String());
      expect(params['from'], endsWith('Z'));
    });

    test('sense dates no envia from/to', () {
      final params = const EventQuery().toQueryParameters();
      expect(params.containsKey('from'), isFalse);
      expect(params.containsKey('to'), isFalse);
    });

    test('les dates compten com a filtre actiu', () {
      expect(EventQuery(from: wednesday).hasFilters, isTrue);
    });

    test('copyWith pot esborrar les dates', () {
      final q = EventQuery(from: wednesday, to: wednesday);
      final cleared = q.copyWith(clearDates: true);
      expect(cleared.from, isNull);
      expect(cleared.to, isNull);
      expect(q.copyWith(page: 2).from, wednesday);
    });
  });
}
