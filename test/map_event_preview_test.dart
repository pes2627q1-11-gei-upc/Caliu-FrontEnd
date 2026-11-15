import 'package:caliu/data/event.dart';
import 'package:caliu/widgets/event_preview_card.dart';
import 'package:caliu/widgets/map_event_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _event = Event(id: 'evt-1', title: 'Festival Sonar Beats');

/// Pantalla inicial amb un botó que obre una segona ruta amb la previsualització,
/// per poder comprovar què fa el botó enrere.
Widget _app({
  required Event? selected,
  required bool active,
  required ValueChanged<Event> onOpen,
  required VoidCallback onClose,
}) {
  return MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => Scaffold(
                  body: Align(
                    alignment: Alignment.bottomCenter,
                    child: MapEventPreview(
                      selected: selected,
                      active: active,
                      onOpen: onOpen,
                      onClose: onClose,
                      now: DateTime(2026, 11, 15),
                    ),
                  ),
                ),
              ),
            ),
            child: const Text('Obrir mapa'),
          ),
        ),
      ),
    ),
  );
}

Future<void> _openMap(WidgetTester tester) async {
  await tester.tap(find.text('Obrir mapa'));
  await tester.pumpAndSettle();
}

Widget _preview({
  required Event? selected,
  required ValueChanged<Event> onOpen,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.bottomCenter,
        child: MapEventPreview(
          selected: selected,
          onOpen: onOpen,
          onClose: () {},
          now: DateTime(2026, 11, 15),
        ),
      ),
    ),
  );
}

void main() {
  group('MapEventPreview: animació', () {
    testWidgets('sense selecció no mostra cap targeta', (tester) async {
      await tester.pumpWidget(_preview(selected: null, onOpen: (_) {}));
      expect(find.byType(EventPreviewCard), findsNothing);
    });

    testWidgets(
      'tocar la targeta mentre desapareix obre el seu esdeveniment',
      (tester) async {
        final opened = <Event>[];
        await tester.pumpWidget(_preview(selected: _event, onOpen: opened.add));
        await tester.pumpAndSettle();

        // Es tanca la selecció: la targeta comença l'animació de sortida.
        await tester.pumpWidget(_preview(selected: null, onOpen: opened.add));
        await tester.pump(const Duration(milliseconds: 40));
        expect(find.byType(EventPreviewCard), findsOneWidget);

        await tester.tap(
          find.byKey(EventPreviewCard.openButtonKey),
          warnIfMissed: false,
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(opened.single.id, 'evt-1');
        expect(find.byType(EventPreviewCard), findsNothing);
      },
    );
  });

  group('MapEventPreview: botó enrere', () {
    testWidgets('amb targeta oberta i pestanya activa, tanca la targeta',
        (tester) async {
      var closed = 0;
      await tester.pumpWidget(
        _app(
          selected: _event,
          active: true,
          onOpen: (_) {},
          onClose: () => closed++,
        ),
      );
      await _openMap(tester);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(closed, 1);
      // No s'ha sortit de la pantalla del mapa.
      expect(find.byType(EventPreviewCard), findsOneWidget);
      expect(find.text('Obrir mapa'), findsNothing);
    });

    testWidgets(
      'amb targeta oberta però pestanya inactiva, no intercepta el botó',
      (tester) async {
        var closed = 0;
        await tester.pumpWidget(
          _app(
            selected: _event,
            active: false,
            onOpen: (_) {},
            onClose: () => closed++,
          ),
        );
        await _openMap(tester);

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();

        expect(closed, 0);
        expect(find.text('Obrir mapa'), findsOneWidget);
      },
    );

    testWidgets('sense targeta, el botó enrere funciona com sempre',
        (tester) async {
      var closed = 0;
      await tester.pumpWidget(
        _app(
          selected: null,
          active: true,
          onOpen: (_) {},
          onClose: () => closed++,
        ),
      );
      await _openMap(tester);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(closed, 0);
      expect(find.text('Obrir mapa'), findsOneWidget);
    });
  });
}
