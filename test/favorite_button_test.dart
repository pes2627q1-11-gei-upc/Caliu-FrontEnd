import 'dart:async';

import 'package:caliu/data/event.dart';
import 'package:caliu/data/favorites_api.dart';
import 'package:caliu/data/favorites_controller.dart';
import 'package:caliu/widgets/favorite_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Servei controlable: cada petició queda pendent fins que el test la resol.
class _ControlledApi implements FavoritesApi {
  final List<Completer<void>> calls = [];
  final List<String> log = [];
  List<Event> initial = const [];

  Future<void> _next(String entry) {
    log.add(entry);
    final completer = Completer<void>();
    calls.add(completer);
    return completer.future;
  }

  @override
  Future<List<Event>> fetchFavorites() async => initial;

  @override
  Future<void> addFavorite(Event event) => _next('add ${event.id}');

  @override
  Future<void> removeFavorite(String eventId) => _next('remove $eventId');

  @override
  Future<bool> isFavorite(String eventId) async =>
      initial.any((e) => e.id == eventId);
}

const _event = Event(id: 'evt-1', title: 'Concert al Parc');
const _other = Event(id: 'evt-2', title: 'Fira del Llibre');

Widget _app(
  FavoritesController controller, {
  List<Event> events = const [_event],
}) => MaterialApp(
  home: Scaffold(
    body: Column(
      children: [
        for (final event in events)
          FavoriteButton(
            key: ValueKey(event.id),
            event: event,
            controller: controller,
          ),
      ],
    ),
  ),
);

Finder _heart(String id, IconData icon) =>
    find.descendant(of: find.byKey(ValueKey(id)), matching: find.byIcon(icon));

void main() {
  group('FavoritesController', () {
    test('load marca els preferits que retorna el servei', () async {
      final api = _ControlledApi()..initial = const [_event];
      final controller = FavoritesController(api);
      await controller.load();
      expect(controller.isLoaded, isTrue);
      expect(controller.isFavorite('evt-1'), isTrue);
      expect(controller.isFavorite('evt-2'), isFalse);
    });

    test('load sense sessió deixa la llista buida sense error', () async {
      final failing = FavoritesController(_UnauthorizedApi());
      await failing.load();
      expect(failing.isLoaded, isFalse);
      expect(failing.isFavorite('evt-1'), isFalse);
    });

    test('toggle és optimista i es confirma quan acaba la petició', () async {
      final api = _ControlledApi();
      final controller = FavoritesController(api);

      final result = controller.toggle(_event);
      expect(controller.isFavorite('evt-1'), isTrue);
      expect(controller.isPending('evt-1'), isTrue);

      api.calls.single.complete();
      expect(await result, isTrue);
      expect(controller.isPending('evt-1'), isFalse);
      expect(api.log, ['add evt-1']);
    });

    test('si la petició falla, desfà el canvi i rellança l\'error', () async {
      final api = _ControlledApi()..initial = const [_event];
      final controller = FavoritesController(api);
      await controller.load();

      final result = controller.toggle(_event);
      expect(controller.isFavorite('evt-1'), isFalse);

      api.calls.single.completeError(
        const FavoritesApiException('Error de xarxa'),
      );
      await expectLater(result, throwsA(isA<FavoritesApiException>()));
      expect(controller.isFavorite('evt-1'), isTrue);
      expect(api.log, ['remove evt-1']);
    });

    test('ignora tocs repetits mentre hi ha una petició en curs', () async {
      final api = _ControlledApi();
      final controller = FavoritesController(api);

      final first = controller.toggle(_event);
      final second = await controller.toggle(_event);
      expect(second, isTrue);
      expect(api.log, ['add evt-1']);

      api.calls.single.complete();
      await first;
      expect(controller.isFavorite('evt-1'), isTrue);
    });
  });

  group('FavoriteButton', () {
    testWidgets('tocar el cor l\'omple a l\'instant', (tester) async {
      final api = _ControlledApi();
      final controller = FavoritesController(api);
      await tester.pumpWidget(_app(controller));

      expect(find.byTooltip('Afegir a preferits'), findsOneWidget);
      await tester.tap(find.byType(FavoriteButton));
      await tester.pump();

      expect(find.byTooltip('Treure de preferits'), findsOneWidget);
      expect(_heart('evt-1', Icons.favorite), findsOneWidget);

      api.calls.single.complete();
      await tester.pumpAndSettle();
      expect(_heart('evt-1', Icons.favorite), findsOneWidget);
    });

    testWidgets('error: torna al cor buit i mostra un SnackBar', (
      tester,
    ) async {
      final api = _ControlledApi();
      final controller = FavoritesController(api);
      await tester.pumpWidget(_app(controller));

      await tester.tap(find.byType(FavoriteButton));
      await tester.pump();
      api.calls.single.completeError(
        const FavoritesApiException(
          'Cal iniciar sessió per gestionar els preferits',
          statusCode: 401,
        ),
      );
      await tester.pumpAndSettle();

      expect(_heart('evt-1', Icons.favorite_border), findsOneWidget);
      expect(
        find.text('Cal iniciar sessió per gestionar els preferits'),
        findsOneWidget,
      );
    });

    testWidgets('dos cors del mateix esdeveniment van sincronitzats', (
      tester,
    ) async {
      final api = _ControlledApi();
      final controller = FavoritesController(api);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                FavoriteButton(
                  key: const ValueKey('fitxa'),
                  event: _event,
                  controller: controller,
                ),
                FavoriteButton(
                  key: const ValueKey('llista'),
                  event: _event,
                  controller: controller,
                ),
                FavoriteButton(
                  key: const ValueKey('evt-2'),
                  event: _other,
                  controller: controller,
                ),
              ],
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('fitxa')));
      api.calls.single.complete();
      await tester.pumpAndSettle();

      expect(_heart('llista', Icons.favorite), findsOneWidget);
      expect(_heart('evt-2', Icons.favorite_border), findsOneWidget);
    });
  });
}

class _UnauthorizedApi implements FavoritesApi {
  static const _error = FavoritesApiException('Sense sessió', statusCode: 401);

  @override
  Future<List<Event>> fetchFavorites() => Future.error(_error);

  @override
  Future<void> addFavorite(Event event) => Future.error(_error);

  @override
  Future<void> removeFavorite(String eventId) => Future.error(_error);

  @override
  Future<bool> isFavorite(String eventId) => Future.error(_error);
}
