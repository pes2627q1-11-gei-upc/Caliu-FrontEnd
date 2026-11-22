import 'package:caliu/data/favorites_api.dart';
import 'package:caliu/data/favorites_controller.dart';
import 'package:caliu/event_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets('Desar i el cor comparteixen els preferits de la fitxa', (
    tester,
  ) async {
    final favorites = FavoritesController(
      MockFavoritesApi(seed: const [], latency: Duration.zero),
    );
    addTearDown(favorites.dispose);

    await http.runWithClient(
      () async {
        await tester.pumpWidget(
          MaterialApp(
            home: EventDetailScreen(eventId: 'evt-1', favorites: favorites),
          ),
        );
        await tester.pumpAndSettle();
      },
      () => MockClient(
        (_) async => http.Response('{"id":"evt-1","title":"Concert"}', 200),
      ),
    );

    expect(find.byIcon(Icons.bookmark_border), findsOneWidget);
    expect(find.byIcon(Icons.favorite_border), findsOneWidget);

    await tester.tap(find.text('Desar'));
    await tester.pumpAndSettle();
    expect(favorites.isFavorite('evt-1'), isTrue);
    expect(favorites.favorites.single.id, 'evt-1');
    expect(find.text('Desat'), findsOneWidget);
    expect(find.byIcon(Icons.bookmark), findsOneWidget);
    expect(find.byIcon(Icons.favorite), findsOneWidget);

    await tester.tap(find.text('Desat'));
    await tester.pumpAndSettle();
    expect(favorites.isFavorite('evt-1'), isFalse);
    expect(find.text('Desar'), findsOneWidget);
    expect(find.byIcon(Icons.bookmark_border), findsOneWidget);
    expect(find.byIcon(Icons.favorite_border), findsOneWidget);

    await tester.tap(find.byTooltip('Afegir a preferits'));
    await tester.pumpAndSettle();
    expect(favorites.isFavorite('evt-1'), isTrue);
    expect(find.text('Desat'), findsOneWidget);
    expect(find.byIcon(Icons.bookmark), findsOneWidget);

    await tester.tap(find.byTooltip('Treure de preferits'));
    await tester.pumpAndSettle();
    expect(favorites.isFavorite('evt-1'), isFalse);
    expect(find.text('Desar'), findsOneWidget);
    expect(find.byIcon(Icons.bookmark_border), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
