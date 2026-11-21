import 'dart:async';
import 'dart:convert';

import 'package:caliu/data/auth_api.dart';
import 'package:caliu/data/auth_session.dart';
import 'package:caliu/data/preferred_radius.dart';
import 'package:caliu/data/search_radius.dart';
import 'package:caliu/preferences_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _Session implements AuthSessionStore {
  _Session([this.token]);

  String? token;

  @override
  Future<String?> readToken() async => token;

  @override
  Future<void> saveToken(String value) async => token = value;

  @override
  Future<void> clear() async => token = null;
}

AuthApi _api(Future<http.Response> Function(http.Request) handler) =>
    AuthApi(client: MockClient(handler), baseUrl: 'http://api.test');

http.Response _prefs({List<String> categories = const [], double? km}) =>
    http.Response(
      jsonEncode({'preferences': categories, 'proximitatKm': km}),
      200,
    );

SearchRadius _radius() =>
    SearchRadius(locate: () async => const LatLng(41.4, 2.17));

void main() {
  group('AuthApi: radi d\'activitat (#124)', () {
    test('llegeix categories i proximitatKm', () async {
      final api = _api((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/users/me/preferences');
        expect(request.headers['authorization'], 'Bearer tok');
        return _prefs(categories: ['Música'], km: 15);
      });

      final preferences = await api.fetchUserPreferences('tok');

      expect(preferences.categories, ['Música']);
      expect(preferences.proximitatKm, 15);
    });

    test(
      'proximitatKm null vol dir sense radi; un tipus erroni falla',
      () async {
        expect(
          (await _api((_) async => _prefs()).fetchUserPreferences('tok'))
              .proximitatKm,
          isNull,
        );
        await expectLater(
          _api(
            (_) async =>
                http.Response('{"preferences":[],"proximitatKm":"10"}', 200),
          ).fetchUserPreferences('tok'),
          throwsA(isA<AuthApiException>()),
        );
      },
    );

    test('desa les categories i el radi, o null per esborrar-lo', () async {
      final bodies = <Object?>[];
      final api = _api((request) async {
        expect(request.method, 'PUT');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        bodies.add(body);
        return _prefs(
          categories: List<String>.from(body['preferences'] as List),
          km: (body['proximitatKm'] as num?)?.toDouble(),
        );
      });

      final saved = await api.saveUserPreferences(
        token: 'tok',
        categories: ['Teatre'],
        proximitatKm: 20,
      );
      await api.saveUserPreferences(
        token: 'tok',
        categories: [],
        proximitatKm: null,
      );

      expect(saved.proximitatKm, 20);
      expect(bodies, [
        {
          'preferences': ['Teatre'],
          'proximitatKm': 20,
        },
        {'preferences': <String>[], 'proximitatKm': null},
      ]);
    });
  });

  group('PreferredRadius', () {
    test('carrega el radi amb sessió; sense sessió o si falla, null', () async {
      final withSession = PreferredRadius(
        api: _api((_) async => _prefs(km: 12)),
        session: _Session('tok'),
      );
      await withSession.load();
      expect(withSession.km, 12);

      final withoutSession = PreferredRadius(
        api: _api((_) async => fail('No ha de cridar l\'API')),
        session: _Session(),
      );
      await withoutSession.load();
      expect(withoutSession.km, isNull);

      final failing = PreferredRadius(
        api: _api((_) async => http.Response('{}', 500)),
        session: _Session('tok'),
      );
      await failing.load();
      expect(failing.km, isNull);
    });

    test('set i clear avisen només quan el valor canvia', () {
      final preferred = PreferredRadius(api: _api((_) async => _prefs()));
      var notifications = 0;
      preferred.addListener(() => notifications++);

      preferred.set(10);
      preferred.set(10);
      preferred.clear();

      expect(preferred.km, isNull);
      expect(notifications, 2);
    });

    test('un set durant una càrrega guanya a la resposta antiga', () async {
      final pending = Completer<http.Response>();
      final preferred = PreferredRadius(
        api: _api((_) => pending.future),
        session: _Session('tok'),
      );

      final load = preferred.load();
      preferred.set(30);
      pending.complete(_prefs(km: 5));
      await load;

      expect(preferred.km, 30);
    });
  });

  group('Radi per defecte al mapa i a la cerca (#125)', () {
    test('aplica el radi desat al filtre compartit', () async {
      final preferred = PreferredRadius(api: _api((_) async => _prefs()))
        ..set(15);
      final radius = _radius();
      final unbind = bindPreferredRadius(preferred, radius);
      await pumpEventQueue();

      expect(radius.radiusKm, 15);
      expect(radius.center, const LatLng(41.4, 2.17));

      preferred.set(25);
      await pumpEventQueue();
      expect(radius.radiusKm, 25);

      unbind();
      radius.dispose();
    });

    test('no trepitja un radi que l\'usuari ha canviat a mà', () async {
      final preferred = PreferredRadius(api: _api((_) async => _prefs()))
        ..set(15);
      final radius = _radius();
      final unbind = bindPreferredRadius(preferred, radius);
      await pumpEventQueue();

      await radius.apply(3);
      preferred.clear();
      await pumpEventQueue();
      expect(
        radius.radiusKm,
        3,
        reason: 'tancar sessió no esborra el radi manual',
      );

      unbind();
      radius.dispose();
    });

    test(
      'en tancar sessió treu el radi que venia de les preferències',
      () async {
        final preferred = PreferredRadius(api: _api((_) async => _prefs()))
          ..set(15);
        final radius = _radius();
        final unbind = bindPreferredRadius(preferred, radius);
        await pumpEventQueue();

        preferred.clear();
        await pumpEventQueue();
        expect(radius.radiusKm, isNull);

        unbind();
        radius.dispose();
      },
    );

    test('sense radi desat, el filtre no canvia', () async {
      final preferred = PreferredRadius(api: _api((_) async => _prefs()));
      final radius = _radius();
      final unbind = bindPreferredRadius(preferred, radius);
      await pumpEventQueue();

      expect(radius.radiusKm, isNull);
      expect(radius.locating, isFalse);

      unbind();
      radius.dispose();
    });
  });

  group('PreferencesScreen: slider de radi (#124)', () {
    Future<List<Map<String, dynamic>>> pumpScreen(
      WidgetTester tester,
      PreferredRadius preferred, {
      double? savedKm,
    }) async {
      final puts = <Map<String, dynamic>>[];
      final api = _api((request) async {
        if (request.url.path == '/events/categories') {
          return http.Response('{"categories":["Música","Teatre"]}', 200);
        }
        if (request.method == 'PUT') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          puts.add(body);
          return _prefs(
            categories: List<String>.from(body['preferences'] as List),
            km: (body['proximitatKm'] as num?)?.toDouble(),
          );
        }
        return _prefs(categories: ['Música'], km: savedKm);
      });
      // Es fa push perquè en desar la pantalla fa pop.
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<bool>(
                  builder: (_) => PreferencesScreen(
                    authApi: api,
                    token: 'tok',
                    preferredRadius: preferred,
                  ),
                ),
              ),
              child: const Text('Obrir'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Obrir'));
      await tester.pumpAndSettle();
      return puts;
    }

    Finder saveButton() => find.text('Desa preferències');

    testWidgets('mostra el radi desat i el desa', (tester) async {
      final preferred = PreferredRadius(api: _api((_) async => _prefs()));
      final puts = await pumpScreen(tester, preferred, savedKm: 12);

      expect(find.text('Radi d’activitat'), findsOneWidget);
      expect(find.text('12 km'), findsOneWidget);
      final slider = tester.widget<Slider>(
        find.byKey(const ValueKey('preferences-radius-slider')),
      );
      expect(slider.value, 12);

      await tester.ensureVisible(saveButton());
      await tester.tap(saveButton());
      await tester.pumpAndSettle();

      expect(puts.single, {
        'preferences': ['Música'],
        'proximitatKm': 12,
      });
      expect(preferred.km, 12);
    });

    testWidgets('sense radi desat, el slider està amagat; activar-lo el desa', (
      tester,
    ) async {
      final preferred = PreferredRadius(api: _api((_) async => _prefs()));
      final puts = await pumpScreen(tester, preferred);

      expect(find.text('Sense límit de distància.'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('preferences-radius-slider')),
        findsNothing,
      );

      await tester.tap(find.byKey(const ValueKey('preferences-radius-switch')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('preferences-radius-slider')),
        findsOneWidget,
      );
      expect(find.text('10 km'), findsOneWidget);

      await tester.ensureVisible(saveButton());
      await tester.tap(saveButton());
      await tester.pumpAndSettle();

      expect(puts.single['proximitatKm'], 10);
      expect(preferred.km, 10);
    });

    testWidgets('desactivar el radi desa null', (tester) async {
      final preferred = PreferredRadius(api: _api((_) async => _prefs()))
        ..set(12);
      final puts = await pumpScreen(tester, preferred, savedKm: 12);

      await tester.tap(find.byKey(const ValueKey('preferences-radius-switch')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(saveButton());
      await tester.tap(saveButton());
      await tester.pumpAndSettle();

      expect(puts.single['proximitatKm'], isNull);
      expect(preferred.km, isNull);
    });
  });
}
