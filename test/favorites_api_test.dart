import 'package:caliu/data/auth_session.dart';
import 'package:caliu/data/event.dart';
import 'package:caliu/data/favorites_api.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeSession implements AuthSessionStore {
  _FakeSession(this.token);

  String? token;

  @override
  Future<String?> readToken() async => token;

  @override
  Future<void> saveToken(String token) async => this.token = token;

  @override
  Future<void> clear() async => token = null;
}

const _concert = Event(id: 'evt-1', title: 'Concert al Parc');
const _fira = Event(id: 'evt-2', title: 'Fira del Llibre');

MockFavoritesApi _api({List<Event> seed = const [], String? token = 'jwt'}) =>
    MockFavoritesApi(
      session: _FakeSession(token),
      seed: seed,
      latency: Duration.zero,
    );

void main() {
  group('MockFavoritesApi', () {
    test('sense seed explícit carrega els preferits simulats', () async {
      final api = MockFavoritesApi(latency: Duration.zero);
      final favorites = await api.fetchFavorites();
      expect(favorites.map((e) => e.id), sampleFavorites.map((e) => e.id));
    });

    test('llista buida si no hi ha preferits', () async {
      expect(await _api().fetchFavorites(), isEmpty);
    });

    test('afegir: apareix a la llista, el més recent primer', () async {
      final api = _api();
      await api.addFavorite(_concert);
      await api.addFavorite(_fira);

      final favorites = await api.fetchFavorites();
      expect(favorites.map((e) => e.id), ['evt-2', 'evt-1']);
      expect(await api.isFavorite('evt-1'), isTrue);
    });

    test('afegir dues vegades no duplica ni canvia l\'ordre', () async {
      final api = _api(seed: [_concert, _fira]);
      await api.addFavorite(_fira);

      final favorites = await api.fetchFavorites();
      expect(favorites.map((e) => e.id), ['evt-1', 'evt-2']);
    });

    test('eliminar treu l\'esdeveniment i és idempotent', () async {
      final api = _api(seed: [_concert, _fira]);
      await api.removeFavorite('evt-1');
      await api.removeFavorite('evt-1');

      final favorites = await api.fetchFavorites();
      expect(favorites.map((e) => e.id), ['evt-2']);
      expect(await api.isFavorite('evt-1'), isFalse);
    });

    test('la llista retornada no es pot modificar des de fora', () async {
      final api = _api(seed: [_concert]);
      final favorites = await api.fetchFavorites();
      expect(() => favorites.add(_fira), throwsUnsupportedError);
    });

    test('esdeveniment sense id: error 400', () async {
      final api = _api();
      await expectLater(
        api.addFavorite(const Event(id: '', title: 'Sense id')),
        throwsA(
          isA<FavoritesApiException>().having(
            (e) => e.statusCode,
            'statusCode',
            400,
          ),
        ),
      );
    });

    test('sense sessió: totes les operacions donen 401', () async {
      final api = _api(seed: [_concert], token: null);
      final unauthorized = throwsA(
        isA<FavoritesApiException>().having(
          (e) => e.isUnauthorized,
          'isUnauthorized',
          isTrue,
        ),
      );

      await expectLater(api.fetchFavorites(), unauthorized);
      await expectLater(api.addFavorite(_fira), unauthorized);
      await expectLater(api.removeFavorite('evt-1'), unauthorized);
      await expectLater(api.isFavorite('evt-1'), unauthorized);
    });

    test('token buit es tracta com a sense sessió', () async {
      final api = _api(token: '');
      await expectLater(
        api.fetchFavorites(),
        throwsA(isA<FavoritesApiException>()),
      );
    });
  });
}
