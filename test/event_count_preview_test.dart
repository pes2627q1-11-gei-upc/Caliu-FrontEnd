import 'dart:async';

import 'package:caliu/data/event_count_preview.dart';
import 'package:caliu/data/event_query.dart';
import 'package:caliu/data/events_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets(
    'agrupa canvis i usa el total encara que demani només un resultat',
    (tester) async {
      final requests = <Uri>[];
      final preview = EventCountPreview(
        EventsApi(
          client: MockClient((request) async {
            requests.add(request.url);
            return http.Response('{"items":[],"total":125}', 200);
          }),
        ),
      );
      preview.update(const EventQuery(q: 'jazz'));
      preview.update(const EventQuery(q: 'teatre', category: 'Arts'));
      expect(preview.loading, isTrue);
      await tester.pump(const Duration(milliseconds: 350));
      expect(requests.length, 1);
      expect(requests.single.queryParameters['q'], 'teatre');
      expect(requests.single.queryParameters['category'], 'Arts');
      expect(requests.single.queryParameters['limit'], '1');
      expect(preview.total, 125);
      expect(preview.loading, isFalse);
      preview.dispose();
    },
  );

  testWidgets(
    'ignora una resposta antiga que arriba després del recompte actual',
    (tester) async {
      final old = Completer<http.Response>();
      final preview = EventCountPreview(
        EventsApi(
          client: MockClient((request) async {
            if (request.url.queryParameters['q'] == 'old') return old.future;
            return http.Response('{"items":[],"total":18}', 200);
          }),
        ),
      );
      preview.update(const EventQuery(q: 'old'));
      await tester.pump(const Duration(milliseconds: 350));
      preview.update(const EventQuery(q: 'new'));
      await tester.pump(const Duration(milliseconds: 350));
      expect(preview.total, 18);
      old.complete(http.Response('{"items":[],"total":999}', 200));
      await tester.pump();
      expect(preview.total, 18);
      preview.dispose();
    },
  );

  testWidgets(
    'espera el GPS, diferencia un error de zero i permet reintentar',
    (tester) async {
      var calls = 0;
      final preview = EventCountPreview(
        EventsApi(
          client: MockClient((_) async {
            calls++;
            return calls == 1
                ? http.Response('{}', 503)
                : http.Response('{"items":[],"total":0}', 200);
          }),
        ),
      );
      preview.update(null);
      await tester.pump(const Duration(milliseconds: 350));
      expect(calls, 0);
      expect(preview.loading, isTrue);
      preview.update(const EventQuery());
      await tester.pump(const Duration(milliseconds: 350));
      expect(preview.error, isNotNull);
      expect(preview.total, isNull);
      preview.update(const EventQuery());
      await tester.pump(const Duration(milliseconds: 350));
      expect(preview.error, isNull);
      expect(preview.total, 0);
      preview.dispose();
    },
  );

  testWidgets('tancar el filtre cancel·la el recompte encara no enviat', (
    tester,
  ) async {
    var calls = 0;
    final preview = EventCountPreview(
      EventsApi(
        client: MockClient((_) async {
          calls++;
          return http.Response('{"items":[],"total":0}', 200);
        }),
      ),
    );
    preview.update(const EventQuery());
    preview.dispose();
    await tester.pump(const Duration(milliseconds: 350));
    expect(calls, 0);
  });
}
