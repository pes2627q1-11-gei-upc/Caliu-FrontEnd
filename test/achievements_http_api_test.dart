import 'dart:convert';

import 'package:caliu/data/achievements_api.dart';
import 'package:caliu/data/achievements_http_api.dart';
import 'package:caliu/data/auth_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _baseUrl = 'http://127.0.0.1:3000';

class _MemorySession implements AuthSessionStore {
  _MemorySession([this.token = 'jwt-prova']);

  String? token;

  @override
  Future<String?> readToken() async => token;

  @override
  Future<void> saveToken(String value) async => token = value;

  @override
  Future<void> clear() async => token = null;
}

(HttpAchievementsApi, List<http.Request>) _api(
  Future<http.Response> Function(http.Request request) handler, {
  AuthSessionStore? session,
}) {
  final requests = <http.Request>[];
  final api = HttpAchievementsApi(
    client: MockClient((request) {
      requests.add(request);
      return handler(request);
    }),
    baseUrl: _baseUrl,
    session: session ?? _MemorySession(),
  );
  return (api, requests);
}

Map<String, dynamic> _item(
  String id, {
  int target = 5,
  int progress = 0,
  bool? unlocked,
}) => {
  'id': id,
  'title': 'Medalla $id',
  'description': 'Regla de $id',
  'icon': 'explore',
  'target': target,
  'progress': progress,
  'unlocked': ?unlocked,
};

Matcher _error({int? status, Object? message}) => throwsA(
  isA<AchievementsApiException>()
      .having((e) => e.statusCode, 'statusCode', status)
      .having((e) => e.message, 'message', message ?? isA<String>()),
);

void main() {
  test('GET /achievements amb el token', () async {
    final (api, requests) = _api(
      (_) async => http.Response(
        jsonEncode({
          'items': [
            _item('first-event', target: 1, progress: 1, unlocked: true),
            _item('explorer', progress: 3, unlocked: false),
          ],
        }),
        200,
      ),
    );

    final achievements = await api.fetchAchievements();

    expect(achievements.map((a) => a.id), ['first-event', 'explorer']);
    expect(achievements.first.unlocked, isTrue);
    expect(achievements.last.progress, 3);
    expect(achievements.last.icon, 'explore');
    expect(requests.single.url.toString(), '$_baseUrl/achievements');
    expect(requests.single.headers['authorization'], 'Bearer jwt-prova');
  });

  test('l\'estat unlocked del servidor mana sobre el càlcul local', () {
    final locked = Achievement.fromJson(
      _item('a', target: 3, progress: 3, unlocked: false),
    );
    final unlocked = Achievement.fromJson(
      _item('b', target: 3, progress: 1, unlocked: true),
    );
    expect(locked.unlocked, isFalse);
    expect(unlocked.unlocked, isTrue);
  });

  test('sense unlocked del servidor, es calcula amb el progrés', () {
    expect(
      Achievement.fromJson(_item('a', target: 3, progress: 3)).unlocked,
      isTrue,
    );
    expect(
      Achievement.fromJson(_item('b', target: 3, progress: 2)).unlocked,
      isFalse,
    );
  });

  test('sense sessió: 401 sense fer cap petició', () async {
    final (api, requests) = _api(
      (_) async => http.Response('', 200),
      session: _MemorySession(null),
    );
    await expectLater(api.fetchAchievements(), _error(status: 401));
    expect(requests, isEmpty);
  });

  test('sessió caducada (401 del servidor)', () async {
    final (api, _) = _api((_) async => http.Response('', 401));
    await expectLater(api.fetchAchievements(), _error(status: 401));
  });

  test('error del servidor', () async {
    final (api, _) = _api((_) async => http.Response('', 500));
    await expectLater(
      api.fetchAchievements(),
      _error(status: 500, message: 'No s\'han pogut carregar els assoliments'),
    );
  });

  test('sense connexió', () async {
    final (api, _) = _api((_) async => throw const _NetworkError());
    await expectLater(
      api.fetchAchievements(),
      _error(message: contains('No s\'ha pogut connectar')),
    );
  });

  test('resposta amb format inesperat', () async {
    final (api, _) = _api((_) async => http.Response('[]', 200));
    await expectLater(
      api.fetchAchievements(),
      _error(message: contains('format esperat')),
    );
  });
}

class _NetworkError implements Exception {
  const _NetworkError();
}
