import 'package:caliu/data/event.dart';
import 'package:caliu/data/event_when.dart';
import 'package:caliu/widgets/event_preview_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

// Diumenge 15/11/2026 a les 17:00
final _now = DateTime(2026, 11, 15, 17, 0);

Event _event({
  String id = 'evt-1',
  String title = 'Festival Sonar Beats',
  DateTime? start,
  DateTime? end,
  List<String> categories = const ['Música en directe'],
  String? venue = 'Parc del Fòrum',
  String? municipality = 'Barcelona',
}) => Event(
  id: id,
  title: title,
  startDate: start,
  endDate: end,
  categories: categories,
  venue: venue,
  municipality: municipality,
  location: const LatLng(41.41, 2.22),
);

Future<void> _pumpCard(
  WidgetTester tester,
  Event event, {
  VoidCallback? onOpen,
  VoidCallback? onClose,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: EventPreviewCard(
            event: event,
            onOpen: onOpen ?? () {},
            onClose: onClose,
            now: _now,
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('previewWhen', () {
    test('avui amb hora', () {
      final e = _event(start: DateTime(2026, 11, 15, 19, 30));
      expect(previewWhen(e, _now), 'Avui · 19:30 h');
    });

    test('demà amb hora', () {
      final e = _event(start: DateTime(2026, 11, 16, 18, 0));
      expect(previewWhen(e, _now), 'Demà · 18:00 h');
    });

    test('un altre dia: dia de la setmana, dia i mes', () {
      final e = _event(start: DateTime(2026, 11, 21, 21, 0));
      expect(previewWhen(e, _now), 'Dissabte 21 de novembre · 21:00 h');
    });

    test("mesos que comencen per vocal fan servir d'", () {
      final e = _event(start: DateTime(2027, 4, 3, 10, 0));
      expect(previewWhen(e, _now), "Dissabte 3 d'abril · 10:00 h");
    });

    test('a les 00:00 no es mostra hora (la font no la té)', () {
      final e = _event(start: DateTime(2026, 11, 16));
      expect(previewWhen(e, _now), 'Demà');
    });

    test('esdeveniment de diversos dies ja començat: "Fins al ..."', () {
      final e = _event(
        start: DateTime(2025, 11, 24),
        end: DateTime(2026, 12, 20, 23, 59),
      );
      expect(previewWhen(e, _now), 'Fins al 20 de desembre');
    });

    test('sense data d\'inici', () {
      expect(previewWhen(_event(), _now), 'Data per confirmar');
    });
  });

  group('EventPreviewCard', () {
    testWidgets('mostra categoria, títol, data i lloc', (tester) async {
      await _pumpCard(tester, _event(start: DateTime(2026, 11, 15, 19, 30)));

      expect(find.text('MÚSICA EN DIRECTE'), findsOneWidget);
      expect(find.text('Festival Sonar Beats'), findsOneWidget);
      expect(find.text('Avui · 19:30 h'), findsOneWidget);
      expect(find.text('Parc del Fòrum, Barcelona'), findsOneWidget);
    });

    testWidgets('sense categoria ni lloc no mostra aquestes línies', (
      tester,
    ) async {
      await _pumpCard(
        tester,
        _event(categories: const [], venue: null, municipality: null),
      );

      expect(find.text('Festival Sonar Beats'), findsOneWidget);
      expect(find.byIcon(Icons.place_outlined), findsNothing);
      expect(find.text('MÚSICA EN DIRECTE'), findsNothing);
    });

    testWidgets('sense imatge mostra el placeholder', (tester) async {
      await _pumpCard(tester, _event());
      expect(find.byIcon(Icons.event), findsOneWidget);
    });

    testWidgets('el botó "Veure fitxa" crida onOpen', (tester) async {
      var opened = 0;
      await _pumpCard(tester, _event(), onOpen: () => opened++);

      expect(find.byTooltip('Veure fitxa'), findsOneWidget);
      await tester.tap(find.byKey(EventPreviewCard.openButtonKey));
      await tester.pump();

      expect(opened, 1);
    });

    testWidgets('tocar la targeta també obre la fitxa', (tester) async {
      var opened = 0;
      await _pumpCard(tester, _event(), onOpen: () => opened++);

      await tester.tap(find.text('Festival Sonar Beats'));
      await tester.pump();

      expect(opened, 1);
    });

    testWidgets('lliscar avall la nansa crida onClose', (tester) async {
      var closed = 0;
      await _pumpCard(tester, _event(), onClose: () => closed++);

      await tester.fling(
        find.byKey(EventPreviewCard.handleKey),
        const Offset(0, 200),
        1000,
      );
      await tester.pumpAndSettle();

      expect(closed, 1);
    });

    testWidgets('lliscar amunt no la tanca', (tester) async {
      var closed = 0;
      await _pumpCard(tester, _event(), onClose: () => closed++);

      await tester.fling(
        find.byKey(EventPreviewCard.handleKey),
        const Offset(0, -200),
        1000,
      );
      await tester.pumpAndSettle();

      expect(closed, 0);
    });
  });
}
