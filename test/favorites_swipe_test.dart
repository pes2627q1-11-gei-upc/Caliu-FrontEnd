import 'dart:async';

import 'package:caliu/data/event.dart';
import 'package:caliu/data/favorites_api.dart';
import 'package:caliu/data/favorites_controller.dart';
import 'package:caliu/favorites_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _concert = Event(id: 'evt-1', title: 'Concert al Parc');
const _fira = Event(id: 'evt-2', title: 'Fira del Llibre');

/// Servei on cada escriptura queda pendent fins que el test la resol.
class _ControlledApi implements FavoritesApi {
  _ControlledApi(List<Event> initial) : _favorites = [...initial];

  final List<Event> _favorites;
  final List<String> log = [];
  final List<Completer<void>> calls = [];

  Future<void> _next(String entry) {
    log.add(entry);
    final completer = Completer<void>();
    calls.add(completer);
    return completer.future;
  }

  @override
  Future<List<Event>> fetchFavorites() async => List.of(_favorites);

  @override
  Future<void> addFavorite(Event event) => _next('add ${event.id}');

  @override
  Future<void> removeFavorite(String eventId) => _next('remove $eventId');

  @override
  Future<bool> isFavorite(String eventId) async =>
      _favorites.any((e) => e.id == eventId);
}

Future<void> _pump(WidgetTester tester, FavoritesController favorites) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: FavoritesList(favorites: favorites, now: DateTime(2026, 11, 18)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _swipe(WidgetTester tester, String id, double dx) async {
  await tester.drag(find.byKey(ValueKey(id)), Offset(dx, 0));
  await tester.pumpAndSettle();
}

void main() {
  test(
    'settled espera la petició en curs i no falla si n\'hi ha cap',
    () async {
      final api = _ControlledApi(const []);
      final controller = FavoritesController(api);
      await controller.settled('evt-1');

      var done = false;
      final toggle = controller.toggle(_concert);
      unawaited(controller.settled('evt-1').then((_) => done = true));
      await Future<void>.delayed(Duration.zero);
      expect(done, isFalse);

      api.calls.single.completeError(const FavoritesApiException('error'));
      await expectLater(toggle, throwsA(isA<FavoritesApiException>()));
      await Future<void>.delayed(Duration.zero);
      expect(done, isTrue);
    },
  );

  group('Swipe a Preferits', () {
    testWidgets('lliscar a l\'esquerra treu el preferit i ofereix desfer', (
      tester,
    ) async {
      final api = MockFavoritesApi(
        seed: const [_concert, _fira],
        latency: Duration.zero,
      );
      await _pump(tester, FavoritesController(api));

      await _swipe(tester, 'evt-1', -500);

      expect(find.text('Concert al Parc'), findsNothing);
      expect(find.text('Fira del Llibre'), findsOneWidget);
      expect(
        find.text('"Concert al Parc" eliminat de preferits'),
        findsOneWidget,
      );
      expect(find.text('Desfer'), findsOneWidget);
      expect(await api.isFavorite('evt-1'), isFalse);
    });

    testWidgets('"Desfer" el torna a la llista i al servidor', (tester) async {
      final api = MockFavoritesApi(
        seed: const [_concert],
        latency: Duration.zero,
      );
      await _pump(tester, FavoritesController(api));
      await _swipe(tester, 'evt-1', -500);
      expect(find.text('Encara no tens preferits'), findsOneWidget);

      await tester.tap(find.text('Desfer'));
      await tester.pumpAndSettle();

      expect(find.text('Concert al Parc'), findsOneWidget);
      expect(await api.isFavorite('evt-1'), isTrue);
    });

    testWidgets('lliscar a la dreta no fa res', (tester) async {
      final favorites = FavoritesController(
        MockFavoritesApi(seed: const [_concert], latency: Duration.zero),
      );
      await _pump(tester, favorites);

      await _swipe(tester, 'evt-1', 500);

      expect(find.text('Concert al Parc'), findsOneWidget);
      expect(favorites.isFavorite('evt-1'), isTrue);
    });

    testWidgets('treure amb el cor també ofereix desfer', (tester) async {
      final favorites = FavoritesController(
        MockFavoritesApi(seed: const [_concert], latency: Duration.zero),
      );
      await _pump(tester, favorites);

      await tester.tap(find.byTooltip('Treure de preferits'));
      await tester.pumpAndSettle();
      expect(
        find.text('"Concert al Parc" eliminat de preferits'),
        findsOneWidget,
      );

      await tester.tap(find.text('Desfer'));
      await tester.pumpAndSettle();
      expect(favorites.isFavorite('evt-1'), isTrue);
    });

    testWidgets('treure amb el cor: si falla, l\'error substitueix "Desfer"', (
      tester,
    ) async {
      final api = _ControlledApi(const [_concert]);
      final favorites = FavoritesController(api);
      await _pump(tester, favorites);

      await tester.tap(find.byTooltip('Treure de preferits'));
      await tester.pumpAndSettle();
      expect(find.text('Desfer'), findsOneWidget);

      api.calls.single.completeError(
        const FavoritesApiException('Error de xarxa', statusCode: 503),
      );
      await tester.pumpAndSettle();

      expect(find.text('Concert al Parc'), findsOneWidget);
      expect(favorites.isFavorite('evt-1'), isTrue);
      expect(find.text('Error de xarxa'), findsOneWidget);
      expect(find.text('Desfer'), findsNothing);
      expect(
        find.text('"Concert al Parc" eliminat de preferits'),
        findsNothing,
      );
    });

    testWidgets('si falla l\'eliminació, torna a sortir i explica l\'error', (
      tester,
    ) async {
      final api = _ControlledApi(const [_concert]);
      final favorites = FavoritesController(api);
      await _pump(tester, favorites);

      await _swipe(tester, 'evt-1', -500);
      expect(find.text('Concert al Parc'), findsNothing);

      api.calls.single.completeError(
        const FavoritesApiException('Error de xarxa', statusCode: 503),
      );
      await tester.pumpAndSettle();

      expect(find.text('Concert al Parc'), findsOneWidget);
      expect(find.text('Error de xarxa'), findsOneWidget);
      expect(find.text('Desfer'), findsNothing);
    });

    testWidgets('"Desfer" abans que acabi l\'eliminació espera i el restaura', (
      tester,
    ) async {
      final api = _ControlledApi(const [_concert]);
      final favorites = FavoritesController(api);
      await _pump(tester, favorites);

      await _swipe(tester, 'evt-1', -500);
      await tester.tap(find.text('Desfer'));
      await tester.pump();
      expect(api.log, ['remove evt-1']);

      api.calls[0].complete();
      await tester.pump();
      expect(api.log, ['remove evt-1', 'add evt-1']);

      api.calls[1].complete();
      await tester.pumpAndSettle();
      expect(favorites.isFavorite('evt-1'), isTrue);
      expect(find.text('Concert al Parc'), findsOneWidget);
    });
  });
}
